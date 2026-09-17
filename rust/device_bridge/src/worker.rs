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

pub fn run_mirror(
    host: String,
    port: u16,
    audio_enabled: bool,
    id: u64,
    s: &std::sync::Arc<Session>,
) -> Result<(), String> {
    let address: SocketAddr = format!("{}:{}", host, port)
        .parse()
        .unwrap_or_else(|_| SocketAddr::from(([127, 0, 0, 1], port)));

    let mut connected = None;
    for _ in 0..30 {
        if s.stopped.load(Ordering::Acquire) {
            return Ok(());
        }
        let Ok(mut video) = TcpStream::connect_timeout(&address, Duration::from_millis(500)) else {
            std::thread::sleep(Duration::from_millis(150));
            continue;
        };
        let _ = video.set_read_timeout(Some(Duration::from_millis(500)));
        let _ = video.set_write_timeout(Some(Duration::from_secs(2)));
        let _ = video.set_nodelay(true);

        let mut audio = None;
        if audio_enabled {
            std::thread::sleep(Duration::from_millis(30));
            let Ok(a) = TcpStream::connect_timeout(&address, Duration::from_millis(500)) else {
                std::thread::sleep(Duration::from_millis(150));
                continue;
            };
            let _ = a.set_read_timeout(Some(Duration::from_millis(500)));
            let _ = a.set_write_timeout(Some(Duration::from_secs(2)));
            let _ = a.set_nodelay(true);
            audio = Some(a);
        }

        std::thread::sleep(Duration::from_millis(30));
        let Ok(control) = TcpStream::connect_timeout(&address, Duration::from_millis(500)) else {
            std::thread::sleep(Duration::from_millis(150));
            continue;
        };
        let _ = control.set_read_timeout(Some(Duration::from_millis(500)));
        let _ = control.set_write_timeout(Some(Duration::from_secs(2)));
        let _ = control.set_nodelay(true);

        let mut dummy = [0u8; 1];
        if stream::read(&mut video, &mut dummy, &s.stopped).is_ok() {
            connected = Some((video, audio, control));
            break;
        }
        std::thread::sleep(Duration::from_millis(150));
    }

    let (mut video, audio, control) = match connected {
        Some(streams) => streams,
        None => return Err("Failed to connect to scrcpy server".into()),
    };

    let mut meta = [0u8; 80];
    stream::read(&mut video, &mut meta, &s.stopped).map_err(|e| e.to_string())?;

    *s.socket.lock().map_err(|_| "Socket lock poisoned")? =
        Some(video.try_clone().map_err(|e| e.to_string())?);
    *s.control_socket.lock().map_err(|_| "Control socket poisoned")? = Some(control);

    s.status.store(1, Ordering::Release);

    let audio_thread = if let Some(audio_socket) = audio {
        let s_clone = s.clone();
        std::thread::Builder::new()
            .name(format!("anydeck-audio-{}", id))
            .spawn(move || {
                let _ = run_mirror_audio(audio_socket, &s_clone);
            })
            .ok()
    } else {
        None
    };

    let mut decoder = Decoder::new(s.frame.clone());
    let mut header = [0u8; 12];
    let mut packet = Vec::new();

    while !s.stopped.load(Ordering::Acquire) {
        if stream::read_packet(&mut video, &mut header, &s.stopped).is_err() {
            break;
        }
        let session_flags = u32::from_be_bytes(header[0..4].try_into().unwrap());
        if session_flags & 0x8000_0000 != 0 {
            continue;
        }
        let packet_pts = u64::from_be_bytes(header[0..8].try_into().unwrap());
        let clean_pts = packet_pts & !((1u64 << 62) | (1u64 << 61));
        let size = u32::from_be_bytes(header[8..12].try_into().unwrap()) as usize;
        if size == 0 {
            continue;
        }
        if size > 32 * 1024 * 1024 {
            return Err("Invalid video packet size".into());
        }
        if packet.len() < size {
            packet.resize(size, 0);
        }
        if stream::read_packet(&mut video, &mut packet[..size], &s.stopped).is_err() {
            break;
        }
        let _ = decoder.decode(&packet[..size], clean_pts);
    }

    let _ = video.shutdown(std::net::Shutdown::Both);
    if let Some(handle) = audio_thread {
        let _ = handle.join();
    }
    if let Ok(mut guard) = s.control_socket.lock() {
        if let Some(c) = guard.take() {
            let _ = c.shutdown(std::net::Shutdown::Both);
        }
    }
    Ok(())
}

fn run_mirror_audio(mut socket: TcpStream, s: &Session) -> Result<(), String> {
    let mut codec_header = [0u8; 4];
    stream::read(&mut socket, &mut codec_header, &s.stopped).map_err(|e| e.to_string())?;
    // 若设备端未成功捕获音频或返回禁用状态（如 [0, 0, 0, 0]），及时退出避免异常读取
    if codec_header != [0, b'r', b'a', b'w'] {
        let _ = socket.shutdown(std::net::Shutdown::Both);
        return Err("Audio stream disabled or unsupported codec".into());
    }
    let mut player = Player::new().ok();
    let mut header = [0u8; 12];
    let mut packet = Vec::new();
    let mut last_muted = false;
    while !s.stopped.load(Ordering::Acquire) {
        if stream::read_packet(&mut socket, &mut header, &s.stopped).is_err() {
            break;
        }
        let pts = u64::from_be_bytes(header[0..8].try_into().unwrap());
        let size = u32::from_be_bytes(header[8..12].try_into().unwrap()) as usize;
        if size == 0 {
            continue;
        }
        if size > 10 * 1024 * 1024 {
            break;
        }
        if packet.len() < size {
            packet.resize(size, 0);
        }
        if stream::read_packet(&mut socket, &mut packet[..size], &s.stopped).is_err() {
            break;
        }
        let is_config = (pts & (1u64 << 63)) != 0 || (pts & (1u64 << 62)) != 0;
        if !is_config {
            if let Some(player) = player.as_mut() {
                let muted = s.muted.load(Ordering::Acquire);
                if muted != last_muted {
                    let _ = player.mute(muted);
                    last_muted = muted;
                }
                let _ = player.write(&packet[..size]);
            }
        }
    }
    let _ = socket.shutdown(std::net::Shutdown::Both);
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
            control_socket: Mutex::new(None),
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
    #[test]
    fn control_socket_writes_successfully() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let client = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let server = std::thread::spawn(move || {
            let (mut socket, _) = listener.accept().unwrap();
            let mut buf = [0u8; 5];
            socket.read_exact(&mut buf).unwrap();
            assert_eq!(&buf, &[1, 2, 3, 4, 5]);
        });
        let s = state();
        *s.control_socket.lock().unwrap() = Some(client);
        let msg = [1u8, 2, 3, 4, 5];
        let Ok(mut guard) = s.control_socket.lock() else { panic!() };
        let stream = guard.as_mut().unwrap();
        stream.write_all(&msg).unwrap();
        stream.flush().unwrap();
        drop(guard);
        server.join().unwrap();
    }
}
