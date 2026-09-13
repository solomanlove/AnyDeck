//! 单独处理 scrcpy RAW 握手、超时和可中断读取，便于用本地 socket 测试。
use std::io::{self, Read};
use std::net::TcpStream;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

pub fn read(stream: &mut TcpStream, target: &mut [u8], stopped: &AtomicBool) -> io::Result<()> {
    let deadline = Instant::now() + Duration::from_secs(5);
    let mut offset = 0;
    while offset < target.len() {
        if stopped.load(Ordering::Acquire) {
            return Err(io::ErrorKind::Interrupted.into());
        }
        if Instant::now() > deadline {
            return Err(io::ErrorKind::TimedOut.into());
        }
        match stream.read(&mut target[offset..]) {
            Ok(0) => return Err(io::ErrorKind::UnexpectedEof.into()),
            Ok(count) => offset += count,
            Err(error)
                if matches!(
                    error.kind(),
                    io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
                ) => {}
            Err(error) => return Err(error),
        }
    }
    Ok(())
}

pub fn read_packet(
    stream: &mut TcpStream,
    target: &mut [u8],
    stopped: &AtomicBool,
) -> io::Result<()> {
    let mut offset = 0;
    while offset < target.len() {
        if stopped.load(Ordering::Acquire) {
            return Err(io::ErrorKind::Interrupted.into());
        }
        match stream.read(&mut target[offset..]) {
            Ok(0) => return Err(io::ErrorKind::UnexpectedEof.into()),
            Ok(count) => offset += count,
            Err(error)
                if matches!(
                    error.kind(),
                    io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
                ) => {
                std::thread::sleep(Duration::from_millis(2));
            }
            Err(error) => return Err(error),
        }
    }
    Ok(())
}

#[cfg(test)]
pub fn handshake(stream: &mut TcpStream, stopped: &AtomicBool) -> io::Result<()> {
    let mut header = [0; 5];
    read(stream, &mut header, stopped)?;
    if header != [0, 0, b'r', b'a', b'w'] {
        return Err(io::ErrorKind::InvalidData.into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::net::TcpListener;
    fn connection(bytes: Vec<u8>) -> TcpStream {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            for byte in bytes {
                stream.write_all(&[byte]).unwrap();
            }
        });
        TcpStream::connect(address).unwrap()
    }
    #[test]
    fn fragmented_handshake() {
        handshake(
            &mut connection(vec![0, 0, b'r', b'a', b'w']),
            &AtomicBool::new(false),
        )
        .unwrap();
    }
    #[test]
    fn rejects_disabled_audio() {
        assert_eq!(
            handshake(
                &mut connection(vec![0, 0, 0, 0, 0]),
                &AtomicBool::new(false)
            )
            .unwrap_err()
            .kind(),
            io::ErrorKind::InvalidData
        );
    }
    #[test]
    fn cancelled_read_exits() {
        assert_eq!(
            handshake(&mut connection(vec![]), &AtomicBool::new(true))
                .unwrap_err()
                .kind(),
            io::ErrorKind::Interrupted
        );
    }
}
