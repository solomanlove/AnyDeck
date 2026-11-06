//! Direct ADB Socket 客户端：通过 TCP 直连本地 ADB Server (127.0.0.1:5037)，
//! 采用 AOSP 官方 4 字节十六进制长度前缀规范，消除子进程 Fork/Exec 开销。

use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::time::{Duration, Instant};

pub struct AdbSocketClient {
    stream: DeadlineStream,
}

impl AdbSocketClient {
    /// 默认 ADB Server 地址
    const DEFAULT_ADDR: &'static str = "127.0.0.1:5037";

    /// 连接到本地 ADB Server，支持超时控制
    pub fn connect_timeout(timeout: Duration) -> Result<Self, String> {
        let addr: SocketAddr = Self::DEFAULT_ADDR
            .parse()
            .map_err(|e| format!("Invalid ADB server socket address: {e}"))?;

        Self::connect_address(addr, timeout)
    }

    fn connect_address(addr: SocketAddr, timeout: Duration) -> Result<Self, String> {
        let deadline = Instant::now() + timeout;
        let stream = TcpStream::connect_timeout(&addr, timeout)
            .map_err(|e| format!("Failed to connect to ADB server at 127.0.0.1:5037: {e}"))?;

        Ok(Self { stream: DeadlineStream { stream, deadline } })
    }

    /// 发送符合 AOSP 规范的 4 字节 Hex 长度前缀请求，并校验 OKAY 回应
    pub fn send_request(&mut self, payload: &str) -> Result<(), String> {
        let req = format!("{:04x}{}", payload.len(), payload);
        self.stream
            .write_all(req.as_bytes())
            .map_err(|e| format!("Failed to send request payload: {e}"))?;

        let mut status = [0u8; 4];
        self.stream
            .read_exact(&mut status)
            .map_err(|e| format!("Failed to read status response from ADB server: {e}"))?;

        if &status == b"OKAY" {
            Ok(())
        } else if &status == b"FAIL" {
            // 读取 4 字节的错误详情长度
            let mut len_bytes = [0u8; 4];
            if self.stream.read_exact(&mut len_bytes).is_ok() {
                if let Ok(len_str) = std::str::from_utf8(&len_bytes) {
                    if let Ok(len) = usize::from_str_radix(len_str, 16) {
                        let mut err_msg = vec![0u8; len];
                        if self.stream.read_exact(&mut err_msg).is_ok() {
                            return Err(format!(
                                "ADB server returned FAIL: {}",
                                String::from_utf8_lossy(&err_msg)
                            ));
                        }
                    }
                }
            }
            Err("ADB server returned FAIL".into())
        } else {
            Err(format!(
                "Unexpected status from ADB server: {:?}",
                String::from_utf8_lossy(&status)
            ))
        }
    }

    /// 切换会话路由到指定 serial 的设备
    pub fn switch_transport(&mut self, serial: &str) -> Result<(), String> {
        self.send_request(&format!("host:transport:{}", serial))
    }

    /// 执行一次性 Shell 指令，返回全部原生原始输出字节流
    pub fn execute_shell(
        serial: &str,
        command: &str,
        timeout: Duration,
    ) -> Result<Vec<u8>, String> {
        let mut client = Self::connect_timeout(timeout)?;
        client.switch_transport(serial)?;
        client.send_request(&format!("shell:{}", command))?;

        client.read_output()
    }

    /// 输出及总时间双重有界，慢速持续输出也不能绕过整体 deadline。
    fn read_output(&mut self) -> Result<Vec<u8>, String> {
        let mut output = Vec::new();
        let mut buffer = [0u8; 8192];
        loop {
            match self.stream.read(&mut buffer) {
                Ok(0) => break,
                Ok(n) => {
                    if output.len() + n > 1024 * 1024 {
                        return Err("ADB shell output exceeded 1 MiB".into());
                    }
                    output.extend_from_slice(&buffer[..n]);
                }
                Err(error) => return Err(format!("ADB shell read failed: {error}")),
            }
        }

        Ok(output)
    }
}

/// read_exact/write_all 的每次底层 IO 都重算剩余时间，覆盖握手与分块读取。
struct DeadlineStream {
    stream: TcpStream,
    deadline: Instant,
}
impl DeadlineStream {
    fn remaining(&self) -> std::io::Result<Duration> {
        self.deadline.checked_duration_since(Instant::now())
            .filter(|duration| !duration.is_zero())
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::TimedOut, "ADB deadline exceeded"))
    }
}
impl Read for DeadlineStream {
    fn read(&mut self, bytes: &mut [u8]) -> std::io::Result<usize> {
        self.stream.set_read_timeout(Some(self.remaining()?))?;
        self.stream.read(bytes)
    }
}
impl Write for DeadlineStream {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.stream.set_write_timeout(Some(self.remaining()?))?;
        self.stream.write(bytes)
    }
    fn flush(&mut self) -> std::io::Result<()> { self.stream.flush() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;
    use std::thread;

    #[test]
    fn slow_continuous_output_cannot_extend_deadline() {
        let server = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = server.local_addr().unwrap();
        let sender = thread::spawn(move || {
            let (mut peer, _) = server.accept().unwrap();
            for _ in 0..50 {
                if peer.write_all(b"x").is_err() { break; }
                thread::sleep(Duration::from_millis(10));
            }
        });
        let started = Instant::now();
        let mut client = AdbSocketClient::connect_address(address, Duration::from_millis(80)).unwrap();
        assert!(client.read_output().is_err());
        assert!(started.elapsed() < Duration::from_millis(400));
        drop(client);
        sender.join().unwrap();
    }

    #[test]
    fn oversized_output_is_rejected() {
        let server = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = server.local_addr().unwrap();
        let sender = thread::spawn(move || {
            let (mut peer, _) = server.accept().unwrap();
            let _ = peer.write_all(&vec![b'x'; 1024 * 1024 + 1]);
        });
        let mut client = AdbSocketClient::connect_address(address, Duration::from_secs(2)).unwrap();
        assert!(client.read_output().unwrap_err().contains("exceeded"));
        sender.join().unwrap();
    }
}
