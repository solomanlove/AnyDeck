//! native 协议、首帧状态和生命周期回归；loopback 测试不发布 Bonjour。
use super::*;
use crate::airplay::tests::Client;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::atomic::AtomicBool;
use std::time::Duration;

fn server() -> Arc<AirPlayServer> {
    Arc::new(AirPlayServer {
        id: 999998, frame: Arc::new(Frame::default()),
        status: Arc::new(AtomicU8::new(0)),
        stopped: Arc::new(AtomicBool::new(false)),
        last_error: Arc::new(Mutex::new(String::new())),
        _advertiser: Mutex::new(None), task: Mutex::new(None), native: Mutex::new(None),
    })
}

fn request(socket: &mut TcpStream, method: &str, uri: &str, data: &[u8]) -> Vec<u8> {
    let content_type = if method == "GET" { "" } else { "Content-Type: application/octet-stream\r\n" };
    write!(socket, "{method} {uri} RTSP/1.0\r\nCSeq: 1\r\n{content_type}Content-Length: {}\r\n\r\n", data.len()).unwrap();
    socket.write_all(data).unwrap();
    let mut header = Vec::new();
    while !header.ends_with(b"\r\n\r\n") {
        let mut byte = [0];
        socket.read_exact(&mut byte).unwrap();
        header.push(byte[0]);
        assert!(header.len() < 16384);
    }
    let text = String::from_utf8(header).unwrap();
    assert!(text.starts_with("RTSP/1.0 200"), "{text}");
    let len = text.lines().find_map(|line| {
        let (key, value) = line.split_once(':')?;
        key.eq_ignore_ascii_case("content-length").then(|| value.trim().parse::<usize>().unwrap())
    }).unwrap_or(0);
    assert!(len < 1024 * 1024);
    let mut data = vec![0; len];
    socket.read_exact(&mut data).unwrap();
    data
}

#[test]
fn native_pairing_info_restart_and_failed_start_cleanup() {
    let server = server();
    let directory = std::env::temp_dir().join(format!("anydeck-uxplay-test-{}", std::process::id()));
    std::fs::create_dir_all(&directory).unwrap();
    let identity = directory.join("identity.pem");
    let mut previous_key = None;
    for _ in 0..2 {
        let receiver = Receiver::start_with_identity(&server, "AnyDeck-Test", 0, &identity, false).unwrap();
        let port = receiver.port;
        let mut socket = TcpStream::connect(("127.0.0.1", port)).unwrap();
        socket.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
        let info = request(&mut socket, "GET", "/info", &[]);
        let info = plist::Value::from_reader(std::io::Cursor::new(info)).unwrap();
        assert_eq!(info.as_dictionary().unwrap()["name"].as_string(), Some("AnyDeck-Test"));
        let pk = request(&mut socket, "POST", "/pair-setup", &[1; 32]);
        assert_eq!(pk.len(), 32);
        if let Some(expected) = &previous_key { assert_eq!(&pk, expected); }
        previous_key = Some(pk.clone());
        let client = Client::new(90);
        let proof = request(&mut socket, "POST", "/pair-verify", &client.first());
        let second = client.second(&proof, pk.try_into().unwrap(), false);
        assert!(request(&mut socket, "POST", "/pair-verify", &second).is_empty());
        drop(receiver); // 空闲客户端仍连接，停止必须 join 并关闭连接。
        let mut byte = [0];
        assert_eq!(socket.read(&mut byte).unwrap(), 0);
        assert!(std::net::TcpListener::bind(("127.0.0.1", port)).is_ok());
    }
    // 非法名称在已初始化 raop 后失败，必须安全回收而不是返回成功。
    assert!(Receiver::start_with_identity(&server, ".local", 0, &identity, false).is_err());
    std::fs::remove_dir_all(directory).unwrap();
}

#[test]
fn invalid_video_and_reset_never_report_mirroring_or_revive_stopped() {
    let server = server();
    let mut context = Box::new(Context {
        status: server.status.clone(), error: server.last_error.clone(), frame: server.frame.clone(),
        decoder: Mutex::new(Decoder::new(server.frame.clone())),
    });
    let ptr = &mut *context as *mut Context as *mut c_void;
    let bad = [0u8; 4];
    Receiver::on_video_data(ptr, bad.as_ptr(), bad.len() as i32, 0);
    assert_eq!(server.status.load(Ordering::Acquire), AirPlayStatus::Idle as u8);
    assert!(!server.frame.has_surface());
    assert!(server.last_error.lock().unwrap().contains("decode failed"));
    server.stop();
    Receiver::on_video_data(ptr, bad.as_ptr(), bad.len() as i32, 0);
    Receiver::on_stream_reset(ptr);
    assert_eq!(server.status.load(Ordering::Acquire), AirPlayStatus::Stopped as u8);
}

#[test]
fn decoded_surface_reset_and_reconnect() {
    let server = server();
    let mut context = Box::new(Context {
        status: server.status.clone(), error: server.last_error.clone(), frame: server.frame.clone(),
        decoder: Mutex::new(Decoder::new(server.frame.clone())),
    });
    let ptr = &mut *context as *mut Context as *mut c_void;
    let data = include_bytes!("testdata/blue_64x48.h264");
    for _ in 0..2 {
        Receiver::on_video_data(ptr, data.as_ptr(), data.len() as i32, 0);
        assert_eq!(server.status.load(Ordering::Acquire), AirPlayStatus::Mirroring as u8);
        assert!(server.frame.has_surface());
        assert_eq!(server.frame.dimensions(), (64, 48));
        Receiver::on_stream_reset(ptr);
        assert_eq!(server.status.load(Ordering::Acquire), AirPlayStatus::Idle as u8);
        assert!(!server.frame.has_surface());
        assert_eq!(server.frame.dimensions(), (0, 0));
    }
}
