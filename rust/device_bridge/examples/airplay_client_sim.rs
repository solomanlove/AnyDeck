//! AirPlay 只读诊断探针：显式指定服务端口，读取 OPTIONS 与 /info。
//! legacy 加密回归见 cargo test --lib airplay；本工具不证明真机投屏成功。
use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Duration;

/// 按 Content-Length 读取完整响应，避免 TCP 分片导致误判。
fn exchange(socket: &mut TcpStream, request: &[u8]) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    socket.write_all(request)?;
    let mut header = Vec::new();
    while !header.ends_with(b"\r\n\r\n") {
        let mut byte = [0];
        socket.read_exact(&mut byte)?;
        header.push(byte[0]);
        if header.len() > 16 * 1024 { return Err("RTSP header too large".into()); }
    }
    let text = std::str::from_utf8(&header)?;
    if !text.starts_with("RTSP/1.0 200") { return Err(format!("RTSP request failed: {text}").into()); }
    let length = text.lines().filter_map(|line| line.split_once(':'))
        .find(|(key, _)| key.eq_ignore_ascii_case("content-length"))
        .ok_or("Missing Content-Length")?.1.trim().parse::<usize>()?;
    if length > 1024 * 1024 { return Err("RTSP body too large".into()); }
    let mut body = vec![0; length];
    socket.read_exact(&mut body)?;
    Ok(body)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 不扫描或接管其他接收端，不自动启动广播，不修改系统设置。
    let port = std::env::args().nth(1)
        .ok_or("Usage: cargo run --example airplay_client_sim -- <RTSP port>")?.parse::<u16>()?;
    let address = ([127, 0, 0, 1], port).into();
    let mut socket = TcpStream::connect_timeout(&address, Duration::from_secs(3))?;
    socket.set_read_timeout(Some(Duration::from_secs(3)))?;
    socket.set_write_timeout(Some(Duration::from_secs(3)))?;
    exchange(&mut socket, b"OPTIONS * RTSP/1.0\r\nCSeq: 1\r\n\r\n")?;
    let info = exchange(&mut socket, b"GET /info RTSP/1.0\r\nCSeq: 2\r\n\r\n")?;
    let value = plist::Value::from_reader(std::io::Cursor::new(info))?;
    let dict = value.as_dictionary().ok_or("Expected /info dictionary")?;
    println!("RTSP 响应正常；设备名：{}", dict.get("name").and_then(|v| v.as_string()).unwrap_or("unknown"));
    println!("这仅验证信令可达，不代表配对、FairPlay 解密或屏幕画面通过验收。");
    Ok(())
}
