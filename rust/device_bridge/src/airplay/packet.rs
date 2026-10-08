//! AirPlay 128 字节小端视频头与 H.264 avcC/AVCC 解析。
//! 媒体负载须先经会话密钥解密，解析器不能判断密文是否有效。

pub const AIRPLAY_VIDEO_HEADER_LEN: usize = 128;

/// AirPlay 镜像头；options 不是加密标志，不能据此猜测加密方式。
#[derive(Debug, Clone)]
pub struct AirPlayVideoHeader {
    pub payload_size: usize,
    /// 低 8 位：0 视频，1 codec 配置，2 心跳。
    pub payload_type: u16,
    pub options: u16,
    pub pts: u64,
}

impl AirPlayVideoHeader {
    pub fn parse(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() < AIRPLAY_VIDEO_HEADER_LEN {
            return Err("Header buffer too small".into());
        }
        Ok(Self {
            payload_size: u32::from_le_bytes(bytes[0..4].try_into().unwrap()) as usize,
            payload_type: u16::from_le_bytes(bytes[4..6].try_into().unwrap()),
            options: u16::from_le_bytes(bytes[6..8].try_into().unwrap()),
            pts: u64::from_le_bytes(bytes[8..16].try_into().unwrap()),
        })
    }
}

/// AVCC 视频包长度前缀是大端；拒绝残缺包，避免把部分损坏数据交给解码器。
pub fn avcc_to_annex_b(payload: &[u8]) -> Result<Vec<u8>, String> {
    let mut result = Vec::with_capacity(payload.len());
    let mut offset = 0;
    while offset < payload.len() {
        let prefix = payload.get(offset..offset + 4).ok_or("Truncated AVCC length")?;
        let length = u32::from_be_bytes(prefix.try_into().unwrap()) as usize;
        offset += 4;
        if length == 0 || length > payload.len() - offset {
            return Err("Invalid AVCC NAL length".into());
        }
        // 00 00 00 01 也可能是合法的长度 1，不能当作 Annex-B 自动直通。
        result.extend_from_slice(&[0, 0, 0, 1]);
        result.extend_from_slice(&payload[offset..offset + length]);
        offset += length;
    }
    Ok(result)
}

/// type 1 使用 AVCDecoderConfigurationRecord，SPS/PPS 长度为 16 位大端。
pub fn codec_to_annex_b(payload: &[u8]) -> Result<Vec<u8>, String> {
    if payload.len() < 7 || payload[0] != 1 || payload[4] & 3 != 3 {
        return Err("Unsupported avcC configuration (requires 4-byte NAL lengths)".into());
    }
    let mut result = Vec::new();
    let mut offset = 6;
    let sps_count = payload[5] & 31;
    if sps_count == 0 { return Err("avcC has no SPS".into()); }
    for _ in 0..sps_count {
        append_parameter(payload, &mut offset, &mut result, 7)?;
    }
    let pps_count = *payload.get(offset).ok_or("Missing avcC PPS count")?;
    offset += 1;
    if pps_count == 0 { return Err("avcC has no PPS".into()); }
    for _ in 0..pps_count {
        append_parameter(payload, &mut offset, &mut result, 8)?;
    }
    Ok(result)
}

/// 对参数集类型和长度做边界检查，保留高 profile 可选扩展字段。
fn append_parameter(data: &[u8], offset: &mut usize, out: &mut Vec<u8>, kind: u8) -> Result<(), String> {
    let prefix = data.get(*offset..*offset + 2).ok_or("Truncated avcC length")?;
    let length = u16::from_be_bytes(prefix.try_into().unwrap()) as usize;
    *offset += 2;
    let nal = data.get(*offset..*offset + length).ok_or("Truncated avcC parameter")?;
    if nal.is_empty() || nal[0] & 31 != kind {
        return Err("Invalid avcC parameter type".into());
    }
    out.extend_from_slice(&[0, 0, 0, 1]);
    out.extend_from_slice(nal);
    *offset += length;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn little_endian_wire_header() {
        let mut raw = [0; 128];
        // 协议抓包形态，不能用被测解析器生成同一错误端序的样本。
        raw[..16].copy_from_slice(&[0x1f, 0, 0, 0, 1, 0, 6, 0, 0x1d, 0x9a, 0x9f, 0x59, 0xef, 0xde, 0, 0]);
        let header = AirPlayVideoHeader::parse(&raw).unwrap();
        assert_eq!(header.payload_size, 31);
        assert_eq!(header.payload_type, 1);
        assert_eq!(header.options, 6);
        assert_eq!(header.pts, 0x0000deef599f9a1d);
        assert!(AirPlayVideoHeader::parse(&raw[..127]).is_err());
    }

    #[test]
    fn avcc_lengths_and_truncation() {
        assert_eq!(avcc_to_annex_b(&[0,0,0,1,0x65,0,0,0,2,0x61,0xff]).unwrap(),
            [0,0,0,1,0x65,0,0,0,1,0x61,0xff]);
        assert!(avcc_to_annex_b(&[0,0,0,3,0x65]).is_err());
        assert!(avcc_to_annex_b(&[0,0,0,0]).is_err());
        assert!(avcc_to_annex_b(&[0,0]).is_err());
    }

    #[test]
    fn codec_configuration_is_not_video_avcc() {
        let config = [1,0x64,0,0x28,0xff,0xe1,0,2,0x67,0x42,1,0,2,0x68,0xce];
        assert_eq!(codec_to_annex_b(&config).unwrap(), [0,0,0,1,0x67,0x42,0,0,0,1,0x68,0xce]);
        for end in 0..config.len() { assert!(codec_to_annex_b(&config[..end]).is_err()); }
    }
}
