//! Direct ADB Socket 客户端：通过 TCP 直连本地 ADB Server (127.0.0.1:5037)，
//! 采用 AOSP 官方 4 字节十六进制长度前缀规范，消除子进程 Fork/Exec 开销。

use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::time::Duration;

pub struct AdbSocketClient {
    stream: TcpStream,
}

impl AdbSocketClient {
    /// 默认 ADB Server 地址
    const DEFAULT_ADDR: &'static str = "127.0.0.1:5037";

    /// 连接到本地 ADB Server，支持超时控制
    pub fn connect_timeout(timeout: Duration) -> Result<Self, String> {
        let addr: SocketAddr = Self::DEFAULT_ADDR
            .parse()
            .map_err(|e| format!("Invalid ADB server socket address: {e}"))?;

        let stream = TcpStream::connect_timeout(&addr, timeout)
            .map_err(|e| format!("Failed to connect to ADB server at 127.0.0.1:5037: {e}"))?;

        stream
            .set_read_timeout(Some(timeout))
            .map_err(|e| format!("Failed to set read timeout: {e}"))?;
        stream
            .set_write_timeout(Some(timeout))
            .map_err(|e| format!("Failed to set write timeout: {e}"))?;

        Ok(Self { stream })
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

        let mut output = Vec::new();
        // 循环读取直到对端关闭写端（EOF）或超时
        let mut buffer = [0u8; 8192];
        loop {
            match client.stream.read(&mut buffer) {
                Ok(0) => break, // EOF
                Ok(n) => output.extend_from_slice(&buffer[..n]),
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock
                    || e.kind() == std::io::ErrorKind::TimedOut =>
                {
                    // 若已读取到部分内容且超时，退出循环返回当前已读内容
                    if !output.is_empty() {
                        break;
                    }
                    return Err(format!("Timeout executing shell command: {command}"));
                }
                Err(e) => return Err(format!("Error reading shell output: {e}")),
            }
        }

        Ok(output)
    }
}
