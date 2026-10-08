//! AirPlay 投屏服务端总控模块：
//! 组合 Bonjour 发现、RTSP 信令处理、TCP/RTP 视频流接收、解密及 VideoToolbox 原生硬解码。

pub mod bonjour;
pub mod crypto;
pub mod packet;
pub mod rtsp;

use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::{Arc, Mutex};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::task::{JoinHandle, JoinSet};
use std::time::Duration;

use crate::video::{Decoder, Frame};
use bonjour::AirPlayAdvertiser;
use crypto::AirPlayCrypto;
use packet::{avcc_to_annex_b, codec_to_annex_b, AirPlayVideoHeader, AIRPLAY_VIDEO_HEADER_LEN};
use rtsp::{parse_rtsp_request, RtspResponse, RtspSession, MAX_RTSP_BYTES};

/// AirPlay 服务状态
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AirPlayStatus {
    Idle = 0,
    Mirroring = 1,
    Stopped = 2,
}

/// AirPlay 屏幕镜像服务端实例
pub struct AirPlayServer {
    /// 唯一会话 ID
    pub id: u64,
    /// 绑定的视频帧共享容器，直接向 Flutter Texture 提供 CVPixelBuffer
    pub frame: Arc<Frame>,
    /// 当前运行状态
    pub status: Arc<AtomicU8>,
    /// 最近的协商错误，通过 FFI 转发到 Dart 本地诊断日志。
    pub last_error: Mutex<String>,
    /// 运行中断标志
    stopped: Arc<AtomicBool>,
    /// Bonjour 广播句柄
    _advertiser: Mutex<Option<AirPlayAdvertiser>>,
    /// 异步监听任务
    task: Mutex<Option<JoinHandle<()>>>,
}

impl AirPlayServer {
    fn bind_port_range(start_port: u16) -> Result<(std::net::TcpListener, u16), String> {
        // 端口占用时只选择下一可用端口，不修改系统 AirPlay 或终止系统进程。
        let max = start_port.saturating_add(20);
        for port in start_port..=max {
            if let Ok(listener) = std::net::TcpListener::bind(format!("0.0.0.0:{port}")) {
                listener.set_nonblocking(true).map_err(|e| e.to_string())?;
                let actual_port = listener.local_addr().map_err(|e| e.to_string())?.port();
                return Ok((listener, actual_port));
            }
        }
        Err(format!("Could not bind port in range {start_port}..{max}"))
    }

    /// 获取本机活跃网络接口 (en0 等) 的真实硬件 MAC 地址
    pub fn get_local_mac() -> String {
        // 1. 尝试通过路由表获取默认出口网卡 (如 en0)
        if let Ok(output) = std::process::Command::new("route")
            .args(["get", "default"])
            .output()
        {
            let text = String::from_utf8_lossy(&output.stdout);
            for line in text.lines() {
                let line = line.trim();
                if line.starts_with("interface:") {
                    let iface = line.trim_start_matches("interface:").trim();
                    if let Ok(if_out) = std::process::Command::new("ifconfig")
                        .arg(iface)
                        .output()
                    {
                        let if_text = String::from_utf8_lossy(&if_out.stdout);
                        for if_line in if_text.lines() {
                            let if_line = if_line.trim();
                            if if_line.starts_with("ether ") {
                                let mac = if_line.trim_start_matches("ether ").trim();
                                if mac.len() >= 17 {
                                    return mac[..17].to_uppercase();
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. 回退直接检测 en0
        if let Ok(if_out) = std::process::Command::new("ifconfig").arg("en0").output() {
            let if_text = String::from_utf8_lossy(&if_out.stdout);
            for if_line in if_text.lines() {
                let if_line = if_line.trim();
                if if_line.starts_with("ether ") {
                    let mac = if_line.trim_start_matches("ether ").trim();
                    if mac.len() >= 17 {
                        return mac[..17].to_uppercase();
                    }
                }
            }
        }

        // 3. 兜底回退真实已知 MAC
        "06:B1:7C:F4:EB:88".to_string()
    }

    /// 创建并启动 AirPlay 屏幕镜像服务
    /// - `id`: 实例会话 ID
    /// - `name`: 电脑广播名称 (如 "AnyDeck-Mac")
    /// - `rtsp_port`: RTSP 控制信令端口 (通常 7000)
    /// - `video_port`: 视频流接收端口 (通常 7100)
    pub fn start(
        id: u64,
        name: &str,
        rtsp_port: u16,
        video_port: u16,
    ) -> Result<Arc<Self>, String> {
        let frame = Arc::new(Frame::default());
        let status = Arc::new(AtomicU8::new(AirPlayStatus::Idle as u8));
        let stopped = Arc::new(AtomicBool::new(false));
        let mac_addr = Self::get_local_mac();

        // 自动探测可用端口（如 7000 被 macOS ControlCenter 占用则自动切至 7001）
        let (std_rtsp, actual_rtsp_port) = Self::bind_port_range(rtsp_port)?;
        let (std_video, actual_video_port) = Self::bind_port_range(video_port)?;

        // 初始化确定性加密套件并获取 Ed25519 公钥 Hex
        let crypto = AirPlayCrypto::new();
        let pk_hex = crypto.public_key_hex();
        eprintln!(
            "[AirPlay] Initialized: MAC = {}, public key = {}, actual_rtsp_port = {}, actual_video_port = {}",
            mac_addr, pk_hex, actual_rtsp_port, actual_video_port
        );

        // 1. 注册 macOS 系统级 Bonjour 广播，传入严格匹配的 RTSP 端口和 pk_hex
        let advertiser = AirPlayAdvertiser::start(name, &mac_addr, actual_rtsp_port, &pk_hex)?;
        let airplay_txt_bytes = AirPlayAdvertiser::build_airplay_txt(&mac_addr, &pk_hex).as_bytes().to_vec();

        let server = Arc::new(Self {
            id,
            frame: frame.clone(),
            status: status.clone(),
            stopped: stopped.clone(),
            last_error: Mutex::new(String::new()),
            _advertiser: Mutex::new(Some(advertiser)),
            task: Mutex::new(None),
        });

        // 2. 启动异步监听主循环
        let server_clone = server.clone();
        let name_owned = name.to_string();
        let mac_owned = mac_addr.clone();

        let handle = crate::core::BatchManager::runtime().spawn(async move {
            let rtsp_listener = match TcpListener::from_std(std_rtsp) {
                Ok(l) => l,
                Err(e) => {
                    eprintln!("[AirPlay] RTSP listener conversion failed: {e}");
                    server_clone.status.store(AirPlayStatus::Stopped as u8, Ordering::Release);
                    return;
                }
            };

            let video_listener = match TcpListener::from_std(std_video) {
                Ok(l) => l,
                Err(e) => {
                    eprintln!("[AirPlay] Video listener conversion failed: {e}");
                    server_clone.status.store(AirPlayStatus::Stopped as u8, Ordering::Release);
                    return;
                }
            };

            // 创建 VideoToolbox 硬件解码器
            let decoder = Arc::new(Mutex::new(Decoder::new(frame.clone())));

            // 两个监听 future 由同一主任务持有；abort 主任务时同步释放监听。
            tokio::join!(
                Self::run_rtsp_loop(rtsp_listener, server_clone.clone(), &name_owned,
                    &mac_owned, actual_video_port, airplay_txt_bytes),
                Self::run_video_loop(video_listener, server_clone, decoder),
            );
        });

        if let Ok(mut lock) = server.task.lock() {
            *lock = Some(handle);
        }

        Ok(server)
    }

    /// RTSP 控制通道循环：并发处理客户端的信令连接
    async fn run_rtsp_loop(
        listener: TcpListener,
        server: Arc<Self>,
        name: &str,
        mac: &str,
        video_port: u16,
        airplay_txt_bytes: Vec<u8>,
    ) {
        // JoinSet 在父任务取消时中止子连接；不同连接拥有独立配对上下文。
        let mut clients = JoinSet::new();
        while !server.stopped.load(Ordering::Acquire) {
            let accepted = tokio::select! {
                result = clients.join_next(), if !clients.is_empty() => { let _ = result; continue; }
                result = listener.accept() => result,
            };
            let (mut socket, peer) = match accepted {
                Ok(conn) => conn,
                Err(e) => {
                    server.record_error(format!("RTSP accept failed: {e}"));
                    break;
                }
            };
            if clients.len() >= 16 { continue; }

            eprintln!("[AirPlay RTSP] Accepted connection from {peer}");
            let mut sess = RtspSession::new(name, mac, video_port, airplay_txt_bytes.clone());
            let server_clone = server.clone();

            // 为每个连接派发独立异步协程
            clients.spawn(async move {
                let mut buf = Vec::with_capacity(4096);
                let mut temp_buf = [0u8; 2048];

                while !server_clone.stopped.load(Ordering::Acquire) {
                    let n = match tokio::time::timeout(Duration::from_secs(30), socket.read(&mut temp_buf)).await {
                        Ok(Ok(n)) if n > 0 => n,
                        _ => break,
                    };
                    buf.extend_from_slice(&temp_buf[..n]);

                    if buf.len() > MAX_RTSP_BYTES {
                        server_clone.record_error("RTSP request exceeded 1 MiB".into());
                        break;
                    }
                    while !buf.is_empty() {
                        let req = match parse_rtsp_request(&buf) {
                            Ok(req) => req,
                            Err(error) if error == "No header end" || error == "Incomplete body" => break,
                            Err(error) => {
                                server_clone.record_error(error.clone());
                                let response = RtspResponse::error("0", 400, "Bad Request", &error).to_bytes();
                                let _ = tokio::time::timeout(Duration::from_secs(5), socket.write_all(&response)).await;
                                return;
                            }
                        };
                        let total_len = req.total_len;
                        let response = match sess.handle_request(&req) {
                            Ok(response) => response,
                            Err(error) => {
                                let cseq = req.headers.get("cseq").map(String::as_str).unwrap_or("0");
                                RtspResponse::error(cseq, 400, "Bad Request", &error).to_bytes()
                            }
                        };
                        // 只记录响应中的受控错误文本，不记录请求密钥和签名。
                        if !response.starts_with(b"RTSP/1.0 200") {
                            if let Some(pos) = response.windows(4).position(|w| w == b"\r\n\r\n") {
                                server_clone.record_error(format!("{} {}: {}", req.method, req.uri,
                                    String::from_utf8_lossy(&response[pos + 4..])));
                            }
                        }
                        if !matches!(tokio::time::timeout(Duration::from_secs(5), socket.write_all(&response)).await, Ok(Ok(()))) {
                            return;
                        }

                        // 精确移除已处理的信令请求字节，保留管道中后续数据
                        if total_len <= buf.len() {
                            buf.drain(..total_len);
                        } else {
                            buf.clear();
                            break;
                        }
                    }
                }
            });
        }
    }

    /// 视频数据包循环：接收 128 字节头并直接调用 VideoToolbox 解码
    async fn run_video_loop(
        listener: TcpListener,
        server: Arc<Self>,
        decoder: Arc<Mutex<Decoder>>,
    ) {
        while !server.stopped.load(Ordering::Acquire) {
            let (mut socket, peer) = match listener.accept().await {
                Ok(conn) => conn,
                Err(e) => {
                    eprintln!("[AirPlay Video] Accept error: {e}");
                    break;
                }
            };

            eprintln!("[AirPlay Video] Accepted video stream connection from {peer}");
            // 在媒体 SETUP 真正实现前拒绝未授权的视频连接。
            // 后续媒体上下文必须关联 RTSP 客户端及独立的 FairPlay 流密钥。
            if server.status.load(Ordering::Acquire) != AirPlayStatus::Mirroring as u8 {
                server.record_error("Video connection rejected: media SETUP has not completed".into());
                continue;
            }
            let mut header_buf = [0u8; AIRPLAY_VIDEO_HEADER_LEN];

            while !server.stopped.load(Ordering::Acquire) {
                // 1. 读取固定 128 字节头
                if socket.read_exact(&mut header_buf).await.is_err() {
                    break;
                }

                let Ok(header) = AirPlayVideoHeader::parse(&header_buf) else {
                    break;
                };

                if header.payload_size > 10 * 1024 * 1024 {
                    server.record_error("AirPlay video payload too large".into());
                    break; // 必须断开，不能把未消费的 payload 当作下一帧头。
                }
                if header.payload_size == 0 { continue; }

                // 2. 读取有效视频负载
                let mut payload = vec![0u8; header.payload_size];
                if socket.read_exact(&mut payload).await.is_err() {
                    break;
                }

                // 3. 转换为 Annex-B 格式
                let annex_b = match header.payload_type & 0xff {
                    1 => codec_to_annex_b(&payload),
                    0 => avcc_to_annex_b(&payload),
                    2 => continue,
                    _ => Err("Unsupported AirPlay video packet type".into()),
                };
                let annex_b = match annex_b {
                    Ok(data) => data,
                    Err(error) => { server.record_error(error); break; }
                };

                // 4. 调用原生 VideoToolbox 硬解码渲染到 CVPixelBuffer
                if let Ok(mut dec) = decoder.lock() {
                    if let Err(error) = dec.decode(&annex_b, header.pts) {
                        server.record_error(format!("VideoToolbox decode failed: {error}"));
                        break;
                    }
                }
            }
        }
    }

    /// 只保留最后一条有界错误，供现有 Dart 日志采集链路读取。
    fn record_error(&self, error: String) {
        eprintln!("[AirPlay] {error}");
        if let Ok(mut latest) = self.last_error.lock() {
            *latest = error.chars().take(512).collect();
        }
    }

    /// 停止服务并释放广播与监听
    pub fn stop(&self) {
        self.stopped.store(true, Ordering::Release);
        self.status.store(AirPlayStatus::Stopped as u8, Ordering::Release);
        if let Ok(mut adv) = self._advertiser.lock() {
            adv.take(); // 触发 Drop 注销 Bonjour
        }
        if let Ok(mut task) = self.task.lock() {
            if let Some(h) = task.take() {
                h.abort();
            }
        }
    }
}

impl Drop for AirPlayServer {
    fn drop(&mut self) {
        self.stop();
    }
}

#[cfg(test)]
mod tests;
