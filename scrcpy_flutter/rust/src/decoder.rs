//! 负责管理与 scrcpy-server 的 TCP 通信会话、VideoToolbox 硬件解码及 AudioQueue 原生音频播放。
use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::os::raw::c_void;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use crate::audio_queue::Player;
use crate::video::{Decoder, Frame};
use crate::{ScrcpyAudioCallback, ScrcpyPixelBufferCallback};

pub struct ScrcpyDecoder {
    host: String,
    port: i32,
    audio_enabled: bool,
    frame_cb: ScrcpyPixelBufferCallback,
    audio_cb: ScrcpyAudioCallback,
    opaque: *mut c_void,

    running: Arc<AtomicBool>,
    video_thread: Option<thread::JoinHandle<()>>,
    audio_thread: Option<thread::JoinHandle<()>>,

    control_stream: Arc<Mutex<Option<TcpStream>>>,
}

unsafe impl Send for ScrcpyDecoder {}
unsafe impl Sync for ScrcpyDecoder {}

impl ScrcpyDecoder {
    pub fn new(
        host: String,
        port: i32,
        audio_enabled: bool,
        frame_cb: ScrcpyPixelBufferCallback,
        audio_cb: ScrcpyAudioCallback,
        opaque: *mut c_void,
    ) -> Self {
        Self {
            host,
            port,
            audio_enabled,
            frame_cb,
            audio_cb,
            opaque,
            running: Arc::new(AtomicBool::new(false)),
            video_thread: None,
            audio_thread: None,
            control_stream: Arc::new(Mutex::new(None)),
        }
    }

    pub fn start(&mut self) -> bool {
        if self.running.load(Ordering::SeqCst) {
            return false;
        }
        self.running.store(true, Ordering::SeqCst);

        // 解析主机地址与端口
        let addr = format!("{}:{}", self.host, self.port);
        let resolved_addr = match addr.to_socket_addrs().and_then(|mut iter| {
            iter.next().ok_or(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "Invalid address",
            ))
        }) {
            Ok(addr) => addr,
            Err(e) => {
                println!("[rust_scrcpy] Address resolution failed: {}", e);
                self.running.store(false, Ordering::SeqCst);
                return false;
            }
        };

        // 阶段 1: 建立 TCP 套接字连接（最多尝试 30 次以等待 adb 端口映射就绪）
        let mut connected_streams = None;
        for retry in 0..30 {
            if !self.running.load(Ordering::SeqCst) {
                return false;
            }

            match connect_sockets(resolved_addr, self.audio_enabled) {
                Ok(streams) => {
                    connected_streams = Some(streams);
                    println!("[rust_scrcpy] TCP sockets connected successfully.");
                    break;
                }
                Err(e) => {
                    if retry % 5 == 0 {
                        println!("[rust_scrcpy] Connection failed: {}, retrying...", e);
                    }
                    thread::sleep(Duration::from_millis(200));
                }
            }
        }

        let (mut video_stream, audio_stream, control_stream) = match connected_streams {
            Some(s) => s,
            None => {
                println!("[rust_scrcpy] Failed to connect to scrcpy server after retries.");
                self.running.store(false, Ordering::SeqCst);
                return false;
            }
        };

        // 阶段 2: 从 video socket 读取 dummy byte（验证 server 握手）
        let mut dummy_read_success = false;
        for _dummy_retry in 0..15 {
            if !self.running.load(Ordering::SeqCst) {
                return false;
            }

            let mut dummy = [0u8; 1];
            match video_stream.read(&mut dummy) {
                Ok(1..) => {
                    dummy_read_success = true;
                    break;
                }
                Ok(0) => {
                    thread::sleep(Duration::from_millis(100));
                }
                Err(e) => {
                    if e.kind() == std::io::ErrorKind::WouldBlock
                        || e.kind() == std::io::ErrorKind::TimedOut
                    {
                        thread::sleep(Duration::from_millis(100));
                    } else {
                        break;
                    }
                }
            }
        }

        if !dummy_read_success {
            println!("[rust_scrcpy] Failed to read dummy byte from server.");
            self.running.store(false, Ordering::SeqCst);
            return false;
        }

        // 保存 control stream
        {
            let mut guard = self.control_stream.lock().unwrap();
            *guard = Some(control_stream);
        }

        let running = self.running.clone();
        let frame_cb = self.frame_cb;
        let opaque_val = self.opaque as usize;

        // 启动视频硬解与渲染线程
        self.video_thread = Some(thread::spawn(move || {
            let opaque_ptr = opaque_val as *mut c_void;
            unsafe {
                if let Err(e) = run_decode_loop(running, video_stream, frame_cb, opaque_ptr) {
                    println!("[rust_scrcpy] Video decode loop error: {:?}", e);
                }
            }
        }));

        // 启动音频播放线程
        if self.audio_enabled {
            if let Some(a_stream) = audio_stream {
                let audio_running = self.running.clone();
                let audio_cb = self.audio_cb;
                self.audio_thread = Some(thread::spawn(move || {
                    let opaque_ptr = opaque_val as *mut c_void;
                    unsafe {
                        if let Err(e) =
                            run_audio_loop(audio_running, a_stream, audio_cb, opaque_ptr)
                        {
                            println!("[rust_scrcpy] Audio loop error: {:?}", e);
                        }
                    }
                }));
            }
        }

        true
    }

    pub fn stop(&mut self) {
        self.running.store(false, Ordering::SeqCst);

        // 关闭 control socket 释放读写阻塞
        {
            let mut guard = self.control_stream.lock().unwrap();
            if let Some(stream) = guard.take() {
                let _ = stream.shutdown(std::net::Shutdown::Both);
            }
        }

        if let Some(handle) = self.video_thread.take() {
            let _ = handle.join();
        }
        if let Some(handle) = self.audio_thread.take() {
            let _ = handle.join();
        }
    }

    pub fn send_control_message(&self, bytes: &[u8]) -> bool {
        let guard = self.control_stream.lock().unwrap();
        if let Some(mut stream) = guard.as_ref() {
            if stream.write_all(bytes).is_ok() {
                let _ = stream.flush();
                return true;
            }
        }
        false
    }
}

fn connect_sockets(
    addr: std::net::SocketAddr,
    audio_enabled: bool,
) -> Result<(TcpStream, Option<TcpStream>, TcpStream), String> {
    let video_stream = TcpStream::connect_timeout(&addr, Duration::from_secs(1))
        .map_err(|e| format!("Video socket connect failed: {}", e))?;
    video_stream.set_read_timeout(Some(Duration::from_secs(1))).ok();
    video_stream.set_write_timeout(Some(Duration::from_secs(1))).ok();

    let mut audio_stream = None;
    if audio_enabled {
        thread::sleep(Duration::from_millis(50));
        let stream = TcpStream::connect_timeout(&addr, Duration::from_secs(1))
            .map_err(|e| format!("Audio socket connect failed: {}", e))?;
        stream.set_read_timeout(Some(Duration::from_secs(1))).ok();
        stream.set_write_timeout(Some(Duration::from_secs(1))).ok();
        audio_stream = Some(stream);
    }

    thread::sleep(Duration::from_millis(50));
    let control_stream = TcpStream::connect_timeout(&addr, Duration::from_secs(1))
        .map_err(|e| format!("Control socket connect failed: {}", e))?;
    control_stream.set_read_timeout(Some(Duration::from_secs(1))).ok();
    control_stream.set_write_timeout(Some(Duration::from_secs(1))).ok();

    Ok((video_stream, audio_stream, control_stream))
}

fn read_exactly(
    stream: &mut TcpStream,
    buf: &mut [u8],
    running: &AtomicBool,
) -> Result<(), std::io::Error> {
    let mut total = 0;
    while total < buf.len() {
        if !running.load(Ordering::SeqCst) {
            return Err(std::io::Error::new(
                std::io::ErrorKind::Interrupted,
                "Decoder stopped",
            ));
        }
        match stream.read(&mut buf[total..]) {
            Ok(0) => {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::UnexpectedEof,
                    "Socket closed",
                ))
            }
            Ok(n) => total += n,
            Err(e) => {
                if e.kind() == std::io::ErrorKind::WouldBlock
                    || e.kind() == std::io::ErrorKind::TimedOut
                {
                    thread::sleep(Duration::from_millis(5));
                    continue;
                }
                return Err(e);
            }
        }
    }
    Ok(())
}

/// 运行视频接收与纯 Rust + VideoToolbox 硬解循环。
unsafe fn run_decode_loop(
    running: Arc<AtomicBool>,
    mut video_stream: TcpStream,
    frame_cb: ScrcpyPixelBufferCallback,
    opaque_ptr: *mut c_void,
) -> Result<(), String> {
    let mut meta = [0u8; 80];
    read_exactly(&mut video_stream, &mut meta, &running)
        .map_err(|e| format!("Failed to read metadata: {}", e))?;

    let codec_id = u32::from_be_bytes(meta[64..68].try_into().unwrap());
    let mut current_width = u32::from_be_bytes(meta[72..76].try_into().unwrap()) as i32;
    let mut current_height = u32::from_be_bytes(meta[76..80].try_into().unwrap()) as i32;
    println!(
        "[rust_scrcpy] Metadata: codec_id = {:#x}, width = {}, height = {}",
        codec_id, current_width, current_height
    );

    let frame = Arc::new(Frame::default());
    let mut video_decoder = Decoder::new(frame.clone());

    let mut packet_data = Vec::new();
    let mut header = [0u8; 12];
    let mut decode_error = None;

    while running.load(Ordering::SeqCst) {
        if read_exactly(&mut video_stream, &mut header, &running).is_err() {
            break;
        }

        let (pts, size) = match parse_video_packet_header(&header) {
            VideoPacketHeader::Session {
                width,
                height,
                reset,
            } => {
                current_width = width as i32;
                current_height = height as i32;
                println!(
                    "[rust_scrcpy] Session metadata: width = {}, height = {}, reset = {}",
                    width, height, reset,
                );
                continue;
            }
            VideoPacketHeader::Frame { pts, size } => (pts, size),
        };

        if size > 32 * 1024 * 1024 {
            decode_error = Some(format!(
                "[rust_scrcpy] Video frame size {} exceeds safety threshold 32MB",
                size
            ));
            break;
        }

        if size == 0 {
            continue;
        }

        if packet_data.len() < size {
            packet_data.resize(size, 0);
        }

        if read_exactly(&mut video_stream, &mut packet_data[0..size], &running).is_err() {
            break;
        }

        // 使用 VideoToolbox 进行硬件解码
        if let Err(e) = video_decoder.decode(&packet_data[0..size], pts as u64) {
            if decode_error.is_none() {
                println!("[rust_scrcpy] Decode frame warning: {}", e);
            }
        } else {
            let pixel_buffer = frame.copy();
            if !pixel_buffer.is_null() {
                let (w, h) = frame.dimensions();
                let report_w = if w > 0 { w as i32 } else { current_width };
                let report_h = if h > 0 { h as i32 } else { current_height };
                frame_cb(opaque_ptr, pixel_buffer, report_w, report_h);
                crate::video_ffi::CFRelease(pixel_buffer);
            }
        }
    }

    if let Some(error) = decode_error {
        println!("{}", error);
    }
    println!("[rust_scrcpy] Video decode loop exited gracefully");
    Ok(())
}

#[derive(Debug, PartialEq, Eq)]
enum VideoPacketHeader {
    Session { width: u32, height: u32, reset: bool },
    Frame { pts: i64, size: usize },
}

/// scrcpy 4.0 会在同一视频 socket 内插入 session metadata，用于通知旋转后的新尺寸。
fn parse_video_packet_header(header: &[u8; 12]) -> VideoPacketHeader {
    let session_flags = u32::from_be_bytes(header[0..4].try_into().unwrap());
    if session_flags & 0x8000_0000 != 0 {
        return VideoPacketHeader::Session {
            width: u32::from_be_bytes(header[4..8].try_into().unwrap()),
            height: u32::from_be_bytes(header[8..12].try_into().unwrap()),
            reset: session_flags & 1 != 0,
        };
    }

    let packet_pts = u64::from_be_bytes(header[0..8].try_into().unwrap());
    let clean_pts = packet_pts & !((1u64 << 62) | (1u64 << 61));
    VideoPacketHeader::Frame {
        pts: clean_pts as i64,
        size: u32::from_be_bytes(header[8..12].try_into().unwrap()) as usize,
    }
}

/// 运行音频接收与纯 Rust + AudioQueue 播放循环。
unsafe fn run_audio_loop(
    running: Arc<AtomicBool>,
    mut audio_stream: TcpStream,
    _audio_cb: ScrcpyAudioCallback,
    _opaque_ptr: *mut c_void,
) -> Result<(), String> {
    let mut codec_header = [0u8; 4];
    read_exactly(&mut audio_stream, &mut codec_header, &running)
        .map_err(|e| format!("Failed to read audio codec ID: {}", e))?;

    let codec_str = std::str::from_utf8(&codec_header).unwrap_or("unknown");
    println!("[rust_scrcpy] Audio Codec ID: {}", codec_str);

    let mut player = match Player::new() {
        Ok(p) => Some(p),
        Err(e) => {
            println!("[rust_scrcpy] Failed to initialize AudioQueue: {}", e);
            None
        }
    };

    let mut packet_data = Vec::new();
    let mut header = [0u8; 12];

    while running.load(Ordering::SeqCst) {
        if read_exactly(&mut audio_stream, &mut header, &running).is_err() {
            break;
        }

        let pts = u64::from_be_bytes(header[0..8].try_into().unwrap());
        let size = u32::from_be_bytes(header[8..12].try_into().unwrap()) as usize;

        if size > 10 * 1024 * 1024 {
            return Err(format!(
                "[rust_scrcpy] Audio frame size {} exceeds safety threshold 10MB",
                size
            ));
        }

        if size == 0 {
            continue;
        }

        if packet_data.len() < size {
            packet_data.resize(size, 0);
        }

        if read_exactly(&mut audio_stream, &mut packet_data[0..size], &running).is_err() {
            break;
        }

        let is_config = (pts & (1u64 << 63)) != 0 || (pts & (1u64 << 62)) != 0;
        if !is_config {
            if let Some(player) = player.as_mut() {
                let _ = player.write(&packet_data[0..size]);
            }
        }
    }

    println!("[rust_scrcpy] Audio decode loop exited gracefully");
    Ok(())
}

#[cfg(test)]
mod video_packet_header_tests {
    use super::{parse_video_packet_header, VideoPacketHeader};

    #[test]
    fn parses_rotation_session_metadata() {
        let header = [
            0x80, 0x00, 0x00, 0x01, 0x00, 0x00, 0x09, 0x60, 0x00, 0x00, 0x04, 0x38,
        ];

        assert_eq!(
            parse_video_packet_header(&header),
            VideoPacketHeader::Session {
                width: 2400,
                height: 1080,
                reset: true,
            },
        );
    }

    #[test]
    fn parses_frame_metadata_and_clears_packet_flags() {
        let header = [
            0x60, 0x00, 0x00, 0x00, 0x00, 0x01, 0xe2, 0x40, 0x00, 0x00, 0x10, 0x00,
        ];

        assert_eq!(
            parse_video_packet_header(&header),
            VideoPacketHeader::Frame {
                pts: 123456,
                size: 4096,
            },
        );
    }
}
