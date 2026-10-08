//! RTSP 信令协议解析与处理状态机：
//! 处理 GET /info, pair-setup, pair-verify, SETUP, RECORD, TEARDOWN 等标准 AirPlay 信令。
//! legacy 握手已实现；FairPlay 媒体密钥解包尚未接入。

use std::collections::HashMap;
use super::crypto::AirPlayCrypto;
use super::bonjour::{AIRPLAY_FEATURES, AIRPLAY_STATUS_FLAGS};

/// 限制网络输入，防止错误 Content-Length 导致溢出或无限缓存。
pub const MAX_RTSP_BYTES: usize = 1024 * 1024;

/// RTSP 请求结构体
#[derive(Debug, Default)]
pub struct RtspRequest {
    pub method: String,
    pub uri: String,
    pub headers: HashMap<String, String>,
    pub body: Vec<u8>,
    pub total_len: usize,
}

/// FairPlay 响应消息模板表 (4 种模式，每种 142 字节)
pub const FP_REPLY_MESSAGE: [[u8; 142]; 4] = [
    [
        0x46,0x50,0x4c,0x59,0x03,0x01,0x02,0x00,0x00,0x00,0x00,0x82,0x02,0x00,0x0f,0x9f,
        0x3f,0x9e,0x0a,0x25,0x21,0xdb,0xdf,0x31,0x2a,0xb2,0xbf,0xb2,0x9e,0x8d,0x23,0x2b,
        0x63,0x76,0xa8,0xc8,0x18,0x70,0x1d,0x22,0xae,0x93,0xd8,0x27,0x37,0xfe,0xaf,0x9d,
        0xb4,0xfd,0xf4,0x1c,0x2d,0xba,0x9d,0x1f,0x49,0xca,0xaa,0xbf,0x65,0x91,0xac,0x1f,
        0x7b,0xc6,0xf7,0xe0,0x66,0x3d,0x21,0xaf,0xe0,0x15,0x65,0x95,0x3e,0xab,0x81,0xf4,
        0x18,0xce,0xed,0x09,0x5a,0xdb,0x7c,0x3d,0x0e,0x25,0x49,0x09,0xa7,0x98,0x31,0xd4,
        0x9c,0x39,0x82,0x97,0x34,0x34,0xfa,0xcb,0x42,0xc6,0x3a,0x1c,0xd9,0x11,0xa6,0xfe,
        0x94,0x1a,0x8a,0x6d,0x4a,0x74,0x3b,0x46,0xc3,0xa7,0x64,0x9e,0x44,0xc7,0x89,0x55,
        0xe4,0x9d,0x81,0x55,0x00,0x95,0x49,0xc4,0xe2,0xf7,0xa3,0xf6,0xd5,0xba,
    ],
    [
        0x46,0x50,0x4c,0x59,0x03,0x01,0x02,0x00,0x00,0x00,0x00,0x82,0x02,0x01,0xcf,0x32,
        0xa2,0x57,0x14,0xb2,0x52,0x4f,0x8a,0xa0,0xad,0x7a,0xf1,0x64,0xe3,0x7b,0xcf,0x44,
        0x24,0xe2,0x00,0x04,0x7e,0xfc,0x0a,0xd6,0x7a,0xfc,0xd9,0x5d,0xed,0x1c,0x27,0x30,
        0xbb,0x59,0x1b,0x96,0x2e,0xd6,0x3a,0x9c,0x4d,0xed,0x88,0xba,0x8f,0xc7,0x8d,0xe6,
        0x4d,0x91,0xcc,0xfd,0x5c,0x7b,0x56,0xda,0x88,0xe3,0x1f,0x5c,0xce,0xaf,0xc7,0x43,
        0x19,0x95,0xa0,0x16,0x65,0xa5,0x4e,0x19,0x39,0xd2,0x5b,0x94,0xdb,0x64,0xb9,0xe4,
        0x5d,0x8d,0x06,0x3e,0x1e,0x6a,0xf0,0x7e,0x96,0x56,0x16,0x2b,0x0e,0xfa,0x40,0x42,
        0x75,0xea,0x5a,0x44,0xd9,0x59,0x1c,0x72,0x56,0xb9,0xfb,0xe6,0x51,0x38,0x98,0xb8,
        0x02,0x27,0x72,0x19,0x88,0x57,0x16,0x50,0x94,0x2a,0xd9,0x46,0x68,0x8a,
    ],
    [
        0x46,0x50,0x4c,0x59,0x03,0x01,0x02,0x00,0x00,0x00,0x00,0x82,0x02,0x02,0xc1,0x69,
        0xa3,0x52,0xee,0xed,0x35,0xb1,0x8c,0xdd,0x9c,0x58,0xd6,0x4f,0x16,0xc1,0x51,0x9a,
        0x89,0xeb,0x53,0x17,0xbd,0x0d,0x43,0x36,0xcd,0x68,0xf6,0x38,0xff,0x9d,0x01,0x6a,
        0x5b,0x52,0xb7,0xfa,0x92,0x16,0xb2,0xb6,0x54,0x82,0xc7,0x84,0x44,0x11,0x81,0x21,
        0xa2,0xc7,0xfe,0xd8,0x3d,0xb7,0x11,0x9e,0x91,0x82,0xaa,0xd7,0xd1,0x8c,0x70,0x63,
        0xe2,0xa4,0x57,0x55,0x59,0x10,0xaf,0x9e,0x0e,0xfc,0x76,0x34,0x7d,0x16,0x40,0x43,
        0x80,0x7f,0x58,0x1e,0xe4,0xfb,0xe4,0x2c,0xa9,0xde,0xdc,0x1b,0x5e,0xb2,0xa3,0xaa,
        0x3d,0x2e,0xcd,0x59,0xe7,0xee,0xe7,0x0b,0x36,0x29,0xf2,0x2a,0xfd,0x16,0x1d,0x87,
        0x73,0x53,0xdd,0xb9,0x9a,0xdc,0x8e,0x07,0x00,0x6e,0x56,0xf8,0x50,0xce,
    ],
    [
        0x46,0x50,0x4c,0x59,0x03,0x01,0x02,0x00,0x00,0x00,0x00,0x82,0x02,0x03,0x90,0x01,
        0xe1,0x72,0x7e,0x0f,0x57,0xf9,0xf5,0x88,0x0d,0xb1,0x04,0xa6,0x25,0x7a,0x23,0xf5,
        0xcf,0xff,0x1a,0xbb,0xe1,0xe9,0x30,0x45,0x25,0x1a,0xfb,0x97,0xeb,0x9f,0xc0,0x01,
        0x1e,0xbe,0x0f,0x3a,0x81,0xdf,0x5b,0x69,0x1d,0x76,0xac,0xb2,0xf7,0xa5,0xc7,0x08,
        0xe3,0xd3,0x28,0xf5,0x6b,0xb3,0x9d,0xbd,0xe5,0xf2,0x9c,0x8a,0x17,0xf4,0x81,0x48,
        0x7e,0x3a,0xe8,0x63,0xc6,0x78,0x32,0x54,0x22,0xe6,0xf7,0x8e,0x16,0x6d,0x18,0xaa,
        0x7f,0xd6,0x36,0x25,0x8b,0xce,0x28,0x72,0x6f,0x66,0x1f,0x73,0x88,0x93,0xce,0x44,
        0x31,0x1e,0x4b,0xe6,0xc0,0x53,0x51,0x93,0xe5,0xef,0x72,0xe8,0x68,0x62,0x33,0x72,
        0x9c,0x22,0x7d,0x82,0x0c,0x99,0x94,0x45,0xd8,0x92,0x46,0xc8,0xc3,0x59,
    ],
];

pub const FP_HEADER: [u8; 12] = [
    0x46, 0x50, 0x4c, 0x59, 0x03, 0x01, 0x04, 0x00, 0x00, 0x00, 0x00, 0x14,
];

/// RTSP 响应构建器
pub struct RtspResponse {
    pub status_code: u16,
    pub status_text: &'static str,
    pub cseq: String,
    pub content_type: Option<&'static str>,
    pub body: Vec<u8>,
}

impl RtspResponse {
    pub fn ok(cseq: &str) -> Self {
        Self {
            status_code: 200,
            status_text: "OK",
            cseq: cseq.to_string(),
            content_type: None,
            body: Vec::new(),
        }
    }

    pub fn with_body(mut self, content_type: &'static str, body: Vec<u8>) -> Self {
        self.content_type = Some(content_type);
        self.body = body;
        self
    }

    /// 错误必须有真实 RTSP 响应，不能让发送端只等到超时。
    pub fn error(cseq: &str, code: u16, text: &'static str, detail: &str) -> Self {
        let mut response = Self::ok(cseq).with_body("text/plain", detail.as_bytes().to_vec());
        response.status_code = code;
        response.status_text = text;
        response
    }

    /// 序列化为网络字节流
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut out = format!(
            "RTSP/1.0 {} {}\r\nCSeq: {}\r\nServer: AirTunes/220.68\r\n",
            self.status_code, self.status_text, self.cseq
        );

        if let Some(ct) = self.content_type {
            out.push_str(&format!("Content-Type: {ct}\r\n"));
        }
        out.push_str(&format!("Content-Length: {}\r\n\r\n", self.body.len()));

        let mut bytes = out.into_bytes();
        bytes.extend_from_slice(&self.body);
        bytes
    }
}

/// 解析 RTSP 文本请求
pub fn parse_rtsp_request(raw: &[u8]) -> Result<RtspRequest, String> {
    if raw.len() > MAX_RTSP_BYTES {
        return Err("RTSP request too large".into());
    }
    let needle = b"\r\n\r\n";
    let body_start = raw
        .windows(needle.len())
        .position(|w| w == needle)
        .ok_or("No header end")?
        + needle.len();

    let header_bytes = &raw[..body_start - needle.len()];
    let text = String::from_utf8_lossy(header_bytes);
    let mut lines = text.lines();

    let start_line = lines.next().ok_or("Empty RTSP request")?;
    let mut parts = start_line.split_whitespace();
    let method = parts.next().unwrap_or("").to_string();
    let uri = parts.next().unwrap_or("").to_string();
    if method.is_empty() || uri.is_empty() || parts.next() != Some("RTSP/1.0") {
        return Err("Invalid RTSP request line".into());
    }

    let mut headers = HashMap::new();

    for line in lines {
        if line.is_empty() || line == "\r" {
            break;
        }
        if let Some((k, v)) = line.split_once(':') {
            let key = k.trim().to_lowercase();
            if key == "content-length" && headers.contains_key(&key) {
                return Err("Duplicate Content-Length".into());
            }
            headers.insert(key, v.trim().to_string());
        }
    }

    let content_len = match headers.get("content-length") {
        Some(value) => value.parse::<usize>().map_err(|_| "Invalid Content-Length")?,
        None => 0,
    };
    let total_len = body_start.checked_add(content_len).ok_or("RTSP length overflow")?;
    if total_len > MAX_RTSP_BYTES {
        return Err("RTSP request too large".into());
    }
    if raw.len() < total_len {
        return Err("Incomplete body".into());
    }

    let body = raw[body_start..body_start + content_len].to_vec();

    Ok(RtspRequest {
        method,
        uri,
        headers,
        body,
        total_len: body_start + content_len,
    })
}

/// RTSP 核心会话处理器
pub struct RtspSession {
    pub server_name: String,
    pub mac_address: String,
    pub crypto: AirPlayCrypto,
    pub video_port: u16,
    pub is_mirroring: bool,
    pub airplay_txt_bytes: Vec<u8>,
}

impl RtspSession {
    pub fn new(
        server_name: &str,
        mac_address: &str,
        video_port: u16,
        airplay_txt_bytes: Vec<u8>,
    ) -> Self {
        Self {
            server_name: server_name.to_string(),
            mac_address: mac_address.to_string(),
            crypto: AirPlayCrypto::new(),
            video_port,
            is_mirroring: false,
            airplay_txt_bytes,
        }
    }

    /// 处理单个 RTSP 请求并返回响应字节
    pub fn handle_request(&mut self, req: &RtspRequest) -> Result<Vec<u8>, String> {
        let cseq = req.headers.get("cseq").cloned().unwrap_or_else(|| "1".into());
        eprintln!(
            "[AirPlay RTSP] >>> Received: {} {}, CSeq: {}, BodyLen: {}",
            req.method,
            req.uri,
            cseq,
            req.body.len()
        );

        let res = match req.method.as_str() {
            "OPTIONS" => {
                let headers = "Public: GET, POST, RECORD, SETUP, SET_PARAMETER, TEARDOWN\r\n";
                let bytes = format!(
                    "RTSP/1.0 200 OK\r\nCSeq: {cseq}\r\nServer: AirTunes/220.68\r\n{headers}Content-Length: 0\r\n\r\n"
                ).into_bytes();
                return Ok(bytes);
            }
            "GET" if req.uri.ends_with("/info") => {
                // qualifier 只请求补充 TXT 信息，不应省略身份、公钥和能力字段。
                let mut dict = plist::Dictionary::new();
                dict.insert("deviceID".into(), plist::Value::String(self.mac_address.clone()));
                dict.insert("macAddress".into(), plist::Value::String(self.mac_address.clone()));
                dict.insert("model".into(), plist::Value::String("AppleTV3,2".into()));
                dict.insert("name".into(), plist::Value::String(self.server_name.clone()));
                dict.insert("features".into(), plist::Value::Integer(AIRPLAY_FEATURES.into()));
                dict.insert("statusFlags".into(), plist::Value::Integer(AIRPLAY_STATUS_FLAGS.into()));
                dict.insert("sourceVersion".into(), plist::Value::String("220.68".into()));
                dict.insert("vv".into(), plist::Value::Integer(2.into()));
                dict.insert("pi".into(), plist::Value::String("3e75fac4-1b89-4572-a5ee-4dd121c46872".into()));
                dict.insert("pk".into(), plist::Value::Data(self.crypto.public_key_bytes().to_vec()));
                dict.insert("txtAirPlay".into(), plist::Value::Data(self.airplay_txt_bytes.clone()));

                let mut binary_plist = Vec::new();
                if let Err(e) = plist::Value::Dictionary(dict).to_writer_binary(&mut binary_plist) {
                    eprintln!("[AirPlay RTSP] Binary plist encode failed: {e}");
                }
                RtspResponse::ok(&cseq).with_body("application/x-apple-binary-plist", binary_plist)
            }
            "POST" if req.uri.ends_with("/pair-setup") => {
                if req.body.len() != 32 {
                    RtspResponse::error(&cseq, 400, "Bad Request", "Expected legacy 32-byte pair-setup")
                } else {
                    RtspResponse::ok(&cseq).with_body("application/octet-stream", self.crypto.public_key_bytes().to_vec())
                }
            }
            "POST" if req.uri.ends_with("/pair-verify") => {
                let result = match req.body.first() {
                    Some(1) => self.crypto.handle_pair_verify_1(&req.body),
                    Some(0) => self.crypto.handle_pair_verify_2(&req.body).map(|_| Vec::new()),
                    _ => Err("Invalid legacy pair-verify flag".into()),
                };
                match result {
                    Ok(body) => RtspResponse::ok(&cseq).with_body("application/octet-stream", body),
                    Err(error) => {
                        eprintln!("[AirPlay RTSP] pair-verify failed: {error}");
                        RtspResponse::error(&cseq, 403, "Forbidden", &error)
                    }
                }
            }
            "POST" if req.uri.ends_with("/fp-setup") => {
                if !req.body.starts_with(b"FPLY\x03\x01") {
                    RtspResponse::error(&cseq, 400, "Bad Request", "Unsupported FairPlay header/version")
                } else if req.body.len() == 16 && req.body[6] == 1 && req.body[14] < 4 {
                    let mode = req.body[14] as usize;
                    eprintln!("[AirPlay RTSP] FairPlay setup mode: {mode}");
                    RtspResponse::ok(&cseq).with_body("application/octet-stream", FP_REPLY_MESSAGE[mode].to_vec())
                } else if req.body.len() == 164 && req.body[6] == 3 {
                    eprintln!("[AirPlay RTSP] FairPlay handshake 164 bytes received");
                    let mut resp = Vec::with_capacity(32);
                    resp.extend_from_slice(&FP_HEADER);
                    resp.extend_from_slice(&req.body[144..164]);
                    RtspResponse::ok(&cseq).with_body("application/octet-stream", resp)
                } else {
                    eprintln!("[AirPlay RTSP] FairPlay unknown len {}", req.body.len());
                    RtspResponse::error(&cseq, 400, "Bad Request", "Invalid FairPlay setup message")
                }
            }
            "SETUP" => {
                self.is_mirroring = false;
                if !self.crypto.is_verified() {
                    RtspResponse::error(&cseq, 403, "Forbidden", "pair-verify required before SETUP")
                } else {
                    let value = plist::Value::from_reader(std::io::Cursor::new(&req.body))
                        .map_err(|_| "Invalid SETUP binary plist")?;
                    let dict = value.as_dictionary().ok_or("SETUP must be a dictionary")?;
                    // 不能用配对密钥充当媒体密钥，或忽略 ekey 直接返回虚假成功。
                    let detail = if dict.contains_key("ekey") {
                        "FairPlay media key unwrap is not implemented; encrypted mirroring is unavailable"
                    } else {
                        "AirPlay media SETUP is unavailable until FairPlay, timing and event channels are implemented"
                    };
                    eprintln!("[AirPlay RTSP] SETUP rejected: {detail}");
                    RtspResponse::error(&cseq, 501, "Not Implemented", detail)
                }
            }
            "RECORD" => {
                RtspResponse::error(&cseq, 455, "Method Not Valid in This State", "Media SETUP has not completed")
            }
            "TEARDOWN" => {
                self.is_mirroring = false;
                eprintln!("[AirPlay RTSP] TEARDOWN received, session ended");
                RtspResponse::ok(&cseq)
            }
            "SET_PARAMETER" => {
                RtspResponse::ok(&cseq)
            }
            _ => {
                RtspResponse::error(&cseq, 501, "Not Implemented", "Unsupported RTSP request")
            }
        };

        Ok(res.to_bytes())
    }
}
