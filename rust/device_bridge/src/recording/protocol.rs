//! scrcpy 4.0 压缩包拆分；不解码媒体，长度检查先于内存分配。
use crate::stream;
use std::{io, net::TcpStream, sync::atomic::AtomicBool};

pub const MAX_PACKET: usize = 8 * 1024 * 1024;
pub const CONFIG: u64 = 1 << 62;
pub const KEY: u64 = 1 << 61;

pub struct Packet {
    pub pts: u64,
    pub config: bool,
    pub key: bool,
    pub data: Vec<u8>,
}

pub enum Event {
    Size(u16, u16),
    Video(Packet),
    Audio(Packet),
    AudioDisabled,
}

pub fn read(socket: &mut TcpStream, stopped: &AtomicBool, video: bool) -> Result<Event, String> {
    let mut header = [0; 12];
    stream::read_packet(socket, &mut header, stopped).map_err(|e| e.to_string())?;
    let flags = u64::from_be_bytes(header[..8].try_into().unwrap());
    let size = u32::from_be_bytes(header[8..].try_into().unwrap());
    if flags & (1 << 63) != 0 {
        if !video {
            return Err("Unexpected audio session header".into());
        }
        let width = u32::from_be_bytes(header[4..8].try_into().unwrap());
        if width == 0 || size == 0 || width > u16::MAX as u32 || size > u16::MAX as u32 {
            return Err("Invalid recording dimensions".into());
        }
        return Ok(Event::Size(width as u16, size as u16));
    }
    if size == 0 || size as usize > MAX_PACKET {
        return Err("Invalid recording packet length".into());
    }
    let mut data = vec![0; size as usize];
    stream::read(socket, &mut data, stopped).map_err(|e| e.to_string())?;
    let packet = Packet {
        pts: flags & (KEY - 1),
        config: flags & CONFIG != 0,
        key: flags & KEY != 0,
        data,
    };
    Ok(if video {
        Event::Video(packet)
    } else {
        Event::Audio(packet)
    })
}

/// 支持三/四字节 Annex-B 起始码；返回的 NAL 借用原始 packet。
pub fn nals(data: &[u8]) -> Result<Vec<&[u8]>, String> {
    let mut starts = Vec::new();
    let mut i = 0;
    while i + 3 <= data.len() {
        let prefix = if data[i..].starts_with(&[0, 0, 0, 1]) {
            4
        } else if data[i..].starts_with(&[0, 0, 1]) {
            3
        } else {
            0
        };
        if prefix != 0 {
            starts.push((i, i + prefix));
            i += prefix;
        } else {
            i += 1;
        }
    }
    if starts.first().map(|s| s.0) != Some(0) {
        return Err("Invalid H.264 Annex-B".into());
    }
    let mut result = Vec::new();
    for (index, (_, start)) in starts.iter().enumerate() {
        let end = starts.get(index + 1).map(|s| s.0).unwrap_or(data.len());
        if end <= *start {
            return Err("Empty H.264 NAL".into());
        }
        result.push(&data[*start..end]);
    }
    Ok(result)
}

pub fn codec(socket: &mut TcpStream, stopped: &AtomicBool) -> Result<[u8; 4], String> {
    let mut bytes = [0; 4];
    stream::read(socket, &mut bytes, stopped).map_err(|e: io::Error| e.to_string())?;
    Ok(bytes)
}
