//! 每个会话一个可取消工作线程；不同设备/功能有独立 socket 和临时 server。
use crate::{adb::Transport, audio_queue::Player, stream, video::Decoder, Session};
use std::io::{ErrorKind, Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::sync::atomic::Ordering;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub fn run(
    adb: String,
    serial: String,
    jar: String,
    kind: u8,
    id: u64,
    s: &Session,
) -> Result<(), String> {
    let token = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_nanos() as u64
        ^ id;
    let mut transport = Transport::start(adb, serial, jar, kind, token, &s.stopped)?;
    let address = SocketAddr::from(([127, 0, 0, 1], transport.port));
    let deadline = Instant::now() + Duration::from_secs(15);
    let mut socket = loop {
        if s.stopped.load(Ordering::Acquire) {
            return Ok(());
        }
        if Instant::now() > deadline || !transport.alive() {
            return Err("Device connection failed".into());
        }
        if let Ok(mut socket) = TcpStream::connect_timeout(&address, Duration::from_millis(300)) {
            socket
                .set_read_timeout(Some(Duration::from_millis(100)))
                .map_err(|e| e.to_string())?;
            socket
                .set_write_timeout(Some(Duration::from_secs(2)))
                .map_err(|e| e.to_string())?;
            *s.socket.lock().map_err(|_| "Socket lock poisoned")? =
                Some(socket.try_clone().map_err(|e| e.to_string())?);
            let mut dummy = [0];
            if stream::read(&mut socket, &mut dummy, &s.stopped).is_ok() && dummy[0] == 0 {
                break socket;
            }
        }
        std::thread::sleep(Duration::from_millis(100));
    };
    let result = match kind {
        1 => audio(&mut socket, s),
        2 => clipboard(&mut socket, s),
        _ => camera(&mut socket, s),
    };
    // 必须先 shutdown：AudioRecord / CameraCapture 及时退出，再删除 forward。
    let _ = socket.shutdown(std::net::Shutdown::Both);
    result
}

fn audio(socket: &mut TcpStream, s: &Session) -> Result<(), String> {
    let mut header = [0; 4];
    stream::read(socket, &mut header, &s.stopped).map_err(|e| e.to_string())?;
    if header != [0, b'r', b'a', b'w'] {
        return Err("Microphone disabled".into());
    }
    let mut pcm = [0; 3840];
    stream::read(socket, &mut pcm, &s.stopped).map_err(|e| e.to_string())?;
    let mut player = Player::new()?;
    let mut muted = s.muted.load(Ordering::Acquire);
    player.mute(muted)?;
    player.write(&pcm)?;
    s.status.store(1, Ordering::Release);
    while !s.stopped.load(Ordering::Acquire) {
        stream::read(socket, &mut pcm, &s.stopped).map_err(|e| e.to_string())?;
        let next = s.muted.load(Ordering::Acquire);
        if next != muted {
            player.mute(next)?;
            muted = next;
        }
        player.write(&pcm)?;
    }
    Ok(())
}

fn clipboard(socket: &mut TcpStream, s: &Session) -> Result<(), String> {
    s.status.store(1, Ordering::Release);
    while !s.stopped.load(Ordering::Acquire) {
        if s.refresh.swap(false, Ordering::AcqRel) {
            socket.write_all(&[8, 0]).map_err(|e| e.to_string())?;
        }
        let mut kind = [0];
        match socket.read(&mut kind) {
            Ok(0) => return Err("Clipboard disconnected".into()),
            Ok(_) => {}
            Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => continue,
            Err(e) => return Err(e.to_string()),
        }
        if kind[0] != 0 {
            return Err("Unexpected device message".into());
        }
        let mut header = [0; 4];
        stream::read(socket, &mut header, &s.stopped).map_err(|e| e.to_string())?;
        let length = u32::from_be_bytes(header) as usize;
        if length > 256 * 1024 {
            return Err("Clipboard message too large".into());
        }
        let mut text = vec![0; length];
        stream::read(socket, &mut text, &s.stopped).map_err(|e| e.to_string())?;
        std::str::from_utf8(&text).map_err(|e| e.to_string())?;
        *s.clipboard.lock().map_err(|_| "Clipboard lock poisoned")? = text;
        s.revision.fetch_add(1, Ordering::Release);
    }
    Ok(())
}

fn camera(socket: &mut TcpStream, s: &Session) -> Result<(), String> {
    let mut codec = [0; 4];
    stream::read(socket, &mut codec, &s.stopped).map_err(|e| e.to_string())?;
    if codec != *b"h264" {
        return Err("Unsupported camera codec".into());
    }
    let mut decoder = Decoder::new(s.frame.clone());
    let mut header = [0; 12];
    let mut packet = Vec::new();
    while !s.stopped.load(Ordering::Acquire) {
        stream::read(socket, &mut header, &s.stopped).map_err(|e| e.to_string())?;
        let flags = u64::from_be_bytes(header[..8].try_into().unwrap());
        // v4.0 session metadata 共 12 字节，包含宽高，没有后续 payload。
        if flags & (1 << 63) != 0 {
            continue;
        }
        let length = u32::from_be_bytes(header[8..].try_into().unwrap()) as usize;
        if length == 0 || length > 4 * 1024 * 1024 {
            return Err("Invalid video packet size".into());
        }
        packet.resize(length, 0);
        stream::read(socket, &mut packet, &s.stopped).map_err(|e| e.to_string())?;
        decoder.decode(&packet, flags & !(7 << 61))?;
        if s.frame.dimensions().0 > 0 {
            s.status.store(1, Ordering::Release);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;
    use std::sync::{
        atomic::{AtomicBool, AtomicU64, AtomicU8},
        Arc, Mutex,
    };
    fn state() -> Session {
        Session {
            stopped: AtomicBool::new(false),
            muted: AtomicBool::new(false),
            refresh: AtomicBool::new(true),
            status: AtomicU8::new(0),
            revision: AtomicU64::new(0),
            clipboard: Mutex::new(Vec::new()),
            socket: Mutex::new(None),
            frame: Arc::new(crate::video::Frame::default()),
        }
    }
    #[test]
    fn clipboard_fragmented_unicode_and_refresh() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let mut client = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let server = std::thread::spawn(move || {
            let (mut socket, _) = listener.accept().unwrap();
            let mut request = [0; 2];
            socket.read_exact(&mut request).unwrap();
            assert_eq!(request, [8, 0]);
            let text = "手机🙂剪贴板".as_bytes();
            let mut bytes = vec![0];
            bytes.extend_from_slice(&(text.len() as u32).to_be_bytes());
            bytes.extend_from_slice(text);
            for chunk in bytes.chunks(2) {
                socket.write_all(chunk).unwrap();
            }
        });
        let s = state();
        assert!(clipboard(&mut client, &s).is_err()); // EOF 是正常的测试结束。
        server.join().unwrap();
        assert_eq!(&*s.clipboard.lock().unwrap(), "手机🙂剪贴板".as_bytes());
        assert_eq!(s.revision.load(Ordering::Acquire), 1);
    }
    #[test]
    fn clipboard_rejects_oversize_before_allocation() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let mut client = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let server = std::thread::spawn(move || {
            let (mut socket, _) = listener.accept().unwrap();
            let mut request = [0; 2];
            socket.read_exact(&mut request).unwrap();
            socket.write_all(&[0, 0xff, 0xff, 0xff, 0xff]).unwrap();
        });
        assert_eq!(
            clipboard(&mut client, &state()).unwrap_err(),
            "Clipboard message too large"
        );
        server.join().unwrap();
    }
}
