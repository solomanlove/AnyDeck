//! iOS 设备驱动实现：基于 go-ios CLI 工具链与 WebDriverAgent (WDA) HTTP 自动化协议
use std::path::PathBuf;
use std::sync::OnceLock;
use std::time::Duration;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use super::driver::{DeviceDriver, DevicePlatform};

/// iOS 设备目标条目
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct IosTarget {
    /// 设备唯一标识符 UDID
    pub udid: String,
    /// 设备显示名称 (如 "iPhone 13 Pro")
    pub name: String,
    /// 硬件型号标识 (如 "iPhone14,2")
    pub model: String,
    /// iOS 系统固件版本 (如 "17.4.1")
    pub version: String,
    /// 设备在线状态
    pub status: String,
}

/// 探测宿主机环境中的 go-ios / ios 可执行文件绝对路径
pub fn find_ios_path() -> Result<PathBuf, String> {
    static CACHED_IOS: OnceLock<Option<PathBuf>> = OnceLock::new();

    let path_opt = CACHED_IOS.get_or_init(|| {
        // 1. 优先检查环境变量 GO_IOS_PATH / IOS_PATH
        if let Ok(env_path) = std::env::var("GO_IOS_PATH") {
            let p = PathBuf::from(env_path);
            if p.is_file() {
                return Some(p);
            }
        }
        if let Ok(env_path) = std::env::var("IOS_PATH") {
            let p = PathBuf::from(env_path);
            if p.is_file() {
                return Some(p);
            }
        }

        // 2. 检查常见默认安装路径 (Homebrew / 用户目录 / Go bin)
        let home = std::env::var("HOME").unwrap_or_default();
        let candidates = [
            "/opt/homebrew/bin/ios".to_string(),
            "/usr/local/bin/ios".to_string(),
            "/opt/homebrew/bin/go-ios".to_string(),
            "/usr/local/bin/go-ios".to_string(),
            format!("{home}/go/bin/ios"),
            format!("{home}/go/bin/go-ios"),
            format!("{home}/.local/bin/ios"),
        ];

        for c in &candidates {
            let p = PathBuf::from(c);
            if p.is_file() {
                return Some(p);
            }
        }

        // 3. 检查系统 PATH
        if let Ok(path_var) = std::env::var("PATH") {
            for dir in std::env::split_paths(&path_var) {
                let p1 = dir.join("ios");
                if p1.is_file() {
                    return Some(p1);
                }
                let p2 = dir.join("go-ios");
                if p2.is_file() {
                    return Some(p2);
                }
            }
        }

        None
    });

    path_opt
        .clone()
        .ok_or_else(|| "Could not find 'go-ios' or 'ios' binary in system PATH".into())
}

/// iOS 平台专用设备驱动
pub struct IosDriver {
    udid: String,
    wda_port: u16,
}

impl IosDriver {
    /// 创建指定 UDID 的 iOS 设备驱动实例
    pub fn new(udid: impl Into<String>) -> Self {
        Self {
            udid: udid.into(),
            wda_port: 8100, // 默认 WDA 端口
        }
    }

    /// 设置自定义 WDA 端口
    pub fn with_wda_port(mut self, port: u16) -> Self {
        self.wda_port = port;
        self
    }

    /// 异步执行底层 ios 命令并获取标准输出
    pub async fn run_ios_cmd(args: &[&str], timeout_duration: Duration) -> Result<String, String> {
        let exe = find_ios_path()?;
        let output = tokio::time::timeout(
            timeout_duration,
            tokio::process::Command::new(&exe)
                .args(args)
                .kill_on_drop(true)
                .output(),
        )
        .await
        .map_err(|_| format!("go-ios command timed out after {}s", timeout_duration.as_secs()))?
        .map_err(|e| format!("Failed to spawn go-ios command: {e}"))?;

        let stdout = String::from_utf8_lossy(&output.stdout).to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();

        if !output.status.success() {
            let err_msg = if stderr.is_empty() { stdout } else { stderr };
            return Err(format!("go-ios error (exit code {:?}): {err_msg}", output.status.code()));
        }

        Ok(stdout)
    }

    /// 检索连接至宿主机的已就绪 iOS 设备列表
    pub async fn list_targets() -> Result<Vec<IosTarget>, String> {
        let stdout = Self::run_ios_cmd(&["list", "--details"], Duration::from_secs(10)).await?;
        let mut targets = Vec::new();

        for line in stdout.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            // go-ios 输出可能是单行 JSON，也可能是多行日志中混杂 JSON
            let Ok(val) = serde_json::from_str::<serde_json::Value>(trimmed) else {
                continue;
            };

            let items = if let Some(arr) = val.as_array() {
                arr.clone()
            } else if let Some(arr) = val.get("deviceList").and_then(|v| v.as_array()) {
                arr.clone()
            } else if let Some(arr) = val.get("devices").and_then(|v| v.as_array()) {
                arr.clone()
            } else if val.get("Udid").is_some() || val.get("udid").is_some() || val.get("UniqueIdentifier").is_some() {
                vec![val]
            } else {
                Vec::new()
            };

            for item in items {
                let udid = item.get("Udid")
                    .or_else(|| item.get("udid"))
                    .or_else(|| item.get("UniqueIdentifier"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();

                if udid.is_empty() {
                    continue;
                }

                let name = item.get("ProductName")
                    .or_else(|| item.get("name"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("iPhone")
                    .to_string();

                let model = item.get("ProductType")
                    .or_else(|| item.get("type"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();

                let version = item.get("ProductVersion")
                    .or_else(|| item.get("version"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("iOS")
                    .to_string();

                targets.push(IosTarget {
                    udid,
                    name,
                    model,
                    version,
                    status: "Connected".to_string(),
                });
            }
        }

        Ok(targets)
    }

    /// 向 WDA 发送轻量 HTTP 请求进行自动化操作
    pub async fn wda_request(
        &self,
        endpoint: &str,
        method: &str,
        body_json: Option<&str>,
    ) -> Result<String, String> {
        let port = self.wda_port;
        let url = format!("http://127.0.0.1:{port}{endpoint}");
        Self::execute_http_request(&url, method, body_json, Duration::from_secs(5)).await
    }

    /// 执行轻量级 HTTP 请求 (无第三方重量级 HTTP Client 依赖)
    pub async fn execute_http_request(
        url: &str,
        method: &str,
        body: Option<&str>,
        timeout_duration: Duration,
    ) -> Result<String, String> {
        let parsed_url = url.strip_prefix("http://").ok_or_else(|| "Only http:// is supported".to_string())?;
        let (host_port, path) = match parsed_url.find('/') {
            Some(idx) => (&parsed_url[..idx], &parsed_url[idx..]),
            None => (parsed_url, "/"),
        };

        let host = match host_port.find(':') {
            Some(idx) => host_port[..idx].to_string(),
            None => host_port.to_string(),
        };
        let port: u16 = match host_port.find(':') {
            Some(idx) => host_port[idx + 1..].parse().unwrap_or(80),
            None => 80,
        };

        let method_s = method.to_string();
        let path_s = path.to_string();
        let body_s = body.unwrap_or("").to_string();

        tokio::task::spawn_blocking(move || {
            use std::io::{Read, Write};
            use std::net::{SocketAddr, TcpStream};

            let addr: SocketAddr = format!("{host}:{port}")
                .parse()
                .unwrap_or_else(|_| SocketAddr::from(([127, 0, 0, 1], port)));

            let mut stream = TcpStream::connect_timeout(&addr, timeout_duration)
                .map_err(|e| format!("Connect error: {e}"))?;
            let _ = stream.set_read_timeout(Some(timeout_duration));
            let _ = stream.set_write_timeout(Some(timeout_duration));

            let body_bytes = body_s.as_bytes();
            let request = format!(
                "{method_s} {path_s} HTTP/1.1\r\n\
                 Host: {host}:{port}\r\n\
                 Content-Type: application/json\r\n\
                 Content-Length: {}\r\n\
                 Connection: close\r\n\
                 \r\n",
                body_bytes.len()
            );

            stream.write_all(request.as_bytes()).map_err(|e| e.to_string())?;
            if !body_bytes.is_empty() {
                stream.write_all(body_bytes).map_err(|e| e.to_string())?;
            }

            let mut response = Vec::new();
            stream.read_to_end(&mut response).map_err(|e| e.to_string())?;

            let res_str = String::from_utf8_lossy(&response);
            if let Some(body_start) = res_str.find("\r\n\r\n") {
                Ok(res_str[body_start + 4..].to_string())
            } else {
                Ok(res_str.to_string())
            }
        })
        .await
        .map_err(|e| format!("Tokio join error: {e}"))?
    }
}

#[async_trait]
impl DeviceDriver for IosDriver {
    fn id(&self) -> &str {
        &self.udid
    }

    fn platform(&self) -> DevicePlatform {
        DevicePlatform::Ios
    }

    /// 异步执行指令（支持 go-ios CLI 指令分发）
    async fn execute_shell(&self, cmd: &str) -> Result<String, String> {
        let parts: Vec<&str> = cmd.split_whitespace().collect();
        if parts.is_empty() {
            return Ok(String::new());
        }

        let mut args = parts;
        let udid_arg = format!("--udid={}", self.udid);
        args.push(&udid_arg);

        Self::run_ios_cmd(&args, Duration::from_secs(30)).await
    }

    /// 异步抓取 iOS 全屏截图并返回 PNG 二进制流
    async fn take_screenshot(&self) -> Result<Vec<u8>, String> {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0);
        let pid = std::process::id();
        let local_path = std::env::temp_dir().join(format!("anydeck_ios_{timestamp}_{pid}.png"));
        let local_str = local_path.to_string_lossy().to_string();

        let res = Self::run_ios_cmd(
            &["screenshot", &format!("--output={local_str}"), &format!("--udid={}", self.udid)],
            Duration::from_secs(15),
        )
        .await;

        if res.is_err() {
            // 如果 go-ios 截图失败，尝试 WDA 截图 API 回退
            let wda_url = format!("http://127.0.0.1:{}/screenshot", self.wda_port);
            if let Ok(wda_res) = Self::execute_http_request(&wda_url, "GET", None, Duration::from_secs(5)).await {
                if let Ok(val) = serde_json::from_str::<serde_json::Value>(&wda_res) {
                    if let Some(b64) = val.get("value").and_then(|v| v.as_str()) {
                        // base64 解码 WDA 截图数据 (简单解码器)
                        let clean_b64: String = b64.chars().filter(|c| !c.is_whitespace()).collect();
                        if let Ok(bytes) = base64_decode(&clean_b64) {
                            return Ok(bytes);
                        }
                    }
                }
            }
        }

        res?;

        let bytes = tokio::fs::read(&local_path)
            .await
            .map_err(|e| format!("Failed to read screenshot file: {e}"))?;

        let _ = tokio::fs::remove_file(&local_path).await;

        if bytes.is_empty() {
            return Err("Empty screenshot returned from iOS device".into());
        }

        Ok(bytes)
    }

    /// 推送文件至 iOS 沙盒目录
    async fn push_file(&self, local: &str, remote: &str) -> Result<(), String> {
        Self::run_ios_cmd(
            &[
                "fsync",
                "push",
                &format!("--srcPath={local}"),
                &format!("--dstPath={remote}"),
                &format!("--udid={}", self.udid),
            ],
            Duration::from_secs(180),
        )
        .await?;
        Ok(())
    }
}

/// 简易 Base64 解码实现（避免额外 crate 引入）
fn base64_decode(input: &str) -> Result<Vec<u8>, String> {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut decode_table = [255u8; 256];
    for (i, &b) in TABLE.iter().enumerate() {
        decode_table[b as usize] = i as u8;
    }

    let bytes = input.as_bytes();
    let mut output = Vec::with_capacity(bytes.len() * 3 / 4);
    let mut buffer = 0u32;
    let mut bits_collected = 0;

    for &b in bytes {
        if b == b'=' {
            break;
        }
        let val = decode_table[b as usize];
        if val == 255 {
            continue;
        }
        buffer = (buffer << 6) | (val as u32);
        bits_collected += 6;
        if bits_collected >= 8 {
            bits_collected -= 8;
            output.push((buffer >> bits_collected) as u8);
            buffer &= (1 << bits_collected) - 1;
        }
    }

    Ok(output)
}
