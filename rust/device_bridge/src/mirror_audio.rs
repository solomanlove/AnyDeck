//! Android 投屏音频拆包与输出恢复；网络异常与设备不支持采集分别处理。
use crate::{audio_queue::Player, pcm_playback::PcmPlayback, stream, Session};
use std::{net::TcpStream, sync::atomic::Ordering};

pub(crate) fn run(socket: TcpStream, s: &Session) -> Result<(), String> {
    let mut player = PcmPlayback::new(Player::new);
    receive(socket, s, |pcm, muted| {
        player.write(pcm, muted);
    })
}

fn receive(
    mut socket: TcpStream,
    s: &Session,
    mut write: impl FnMut(&[u8], bool),
) -> Result<(), String> {
    let mut codec_header = [0u8; 4];
    stream::read(&mut socket, &mut codec_header, &s.stopped).map_err(|e| e.to_string())?;
    // 若设备端未成功捕获音频或返回禁用状态（如 [0, 0, 0, 0]），及时退出避免异常读取
    if codec_header != [0, b'r', b'a', b'w'] {
        let _ = socket.shutdown(std::net::Shutdown::Both);
        return Err("Audio stream disabled or unsupported codec".into());
    }
    let mut received_pcm = false;
    let result = (|| -> Result<(), String> {
        let mut header = [0u8; 12];
        let mut packet = Vec::new();
        while !s.stopped.load(Ordering::Acquire) {
            stream::read_packet(&mut socket, &mut header, &s.stopped)
                .map_err(|error| format!("Audio header read failed: {error}"))?;
            let pts = u64::from_be_bytes(header[0..8].try_into().unwrap());
            let size = u32::from_be_bytes(header[8..12].try_into().unwrap()) as usize;
            if size == 0 {
                continue;
            }
            if size > 10 * 1024 * 1024 {
                return Err(format!("Invalid audio packet size: {size}"));
            }
            if packet.len() < size {
                packet.resize(size, 0);
            }
            stream::read_packet(&mut socket, &mut packet[..size], &s.stopped)
                .map_err(|error| format!("Audio payload read failed: {error}"))?;
            let is_config = (pts & (1u64 << 63)) != 0 || (pts & (1u64 << 62)) != 0;
            if !is_config {
                received_pcm = true;
                write(&packet[..size], s.muted.load(Ordering::Acquire));
            }
        }
        Ok(())
    })();
    // 只有曾收到 PCM 的通道异常结束才请求恢复；不支持采集不能触发重连循环。
    if received_pcm && result.is_err() && !s.stopped.load(Ordering::Acquire) {
        s.health.audio_failed.store(true, Ordering::Release);
    }
    let _ = socket.shutdown(std::net::Shutdown::Both);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        io::Write,
        net::TcpListener,
        sync::{
            atomic::{AtomicBool, AtomicU64, AtomicU8},
            Arc, Mutex,
        },
    };

    fn state() -> Session {
        Session {
            stopped: AtomicBool::new(false),
            muted: AtomicBool::new(true),
            refresh: AtomicBool::new(false),
            status: AtomicU8::new(0),
            revision: AtomicU64::new(0),
            clipboard: Mutex::new(Vec::new()),
            socket: Mutex::new(None),
            control_socket: Mutex::new(None),
            frame: Arc::new(crate::video::Frame::default()),
            health: crate::mirror_health::MirrorHealth::default(),
        }
    }

    fn feed(bytes: Vec<u8>, session: &Session) -> (String, usize) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let socket = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let sender = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            for chunk in bytes.chunks(2) {
                stream.write_all(chunk).unwrap();
            }
        });
        let mut count = 0;
        let error = receive(socket, session, |pcm, muted| {
            assert_eq!(pcm, &[1, 2, 3, 4]);
            assert!(muted);
            count += 1;
        })
        .unwrap_err();
        sender.join().unwrap();
        (error, count)
    }

    #[test]
    fn working_stream_eof_requests_recovery_and_preserves_fragmented_pcm() {
        let session = state();
        let mut bytes = vec![0, b'r', b'a', b'w'];
        bytes.extend_from_slice(&123u64.to_be_bytes());
        bytes.extend_from_slice(&4u32.to_be_bytes());
        bytes.extend_from_slice(&[1, 2, 3, 4]);
        let (error, count) = feed(bytes, &session);
        assert!(error.contains("Audio header read failed"));
        assert_eq!(count, 1);
        assert!(session.health.audio_failed.load(Ordering::Acquire));
    }

    #[test]
    fn unsupported_audio_does_not_trigger_reconnect_loop() {
        let session = state();
        assert!(feed(vec![0; 4], &session).0.contains("disabled"));
        assert!(!session.health.audio_failed.load(Ordering::Acquire));
    }

    #[test]
    fn oversized_packet_is_rejected_before_allocation() {
        let session = state();
        let mut bytes = vec![0, b'r', b'a', b'w'];
        bytes.extend_from_slice(&0u64.to_be_bytes());
        bytes.extend_from_slice(&u32::MAX.to_be_bytes());
        assert!(feed(bytes, &session)
            .0
            .contains("Invalid audio packet size"));
        assert!(!session.health.audio_failed.load(Ordering::Acquire));
    }
}
