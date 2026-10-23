//! AirPlay 实时音频播放模块（基于 macOS AudioToolbox AudioQueue 硬解 AAC-ELD / AAC-LC / ALAC）。
//! 支持通过原子开关实时静音或恢复音频输出。

use std::ffi::c_void;
use std::ptr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

type Queue = *mut c_void;

#[repr(C)]
struct AudioStreamBasicDescription {
    sample_rate: f64,
    format_id: u32,
    format_flags: u32,
    bytes_per_packet: u32,
    frames_per_packet: u32,
    bytes_per_frame: u32,
    channels_per_frame: u32,
    bits_per_channel: u32,
    reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct AudioStreamPacketDescription {
    start_offset: i64,
    variable_frames_in_packet: u32,
    data_byte_size: u32,
}

#[repr(C)]
struct AudioQueueBuffer {
    capacity: u32,
    data: *mut c_void,
    size: u32,
    user: *mut c_void,
    packet_capacity: u32,
    packets: *mut AudioStreamPacketDescription,
    packet_count: u32,
}

const K_AUDIO_QUEUE_PROPERTY_MAGIC_COOKIE: u32 = u32::from_be_bytes(*b"aqmc");
const K_AUDIO_QUEUE_PARAM_VOLUME: u32 = 1;
const BUFFER_CAPACITY: u32 = 4096;
const BUFFER_COUNT: usize = 16;

#[allow(clashing_extern_declarations)]
#[link(name = "AudioToolbox", kind = "framework")]
extern "C" {
    fn AudioQueueNewOutput(
        format: *const AudioStreamBasicDescription,
        callback: extern "C" fn(*mut c_void, Queue, *mut AudioQueueBuffer),
        user: *mut c_void,
        run_loop: *mut c_void,
        mode: *mut c_void,
        flags: u32,
        queue: *mut Queue,
    ) -> i32;
    fn AudioQueueAllocateBufferWithPacketDescriptions(
        queue: Queue,
        buffer_size: u32,
        num_packets: u32,
        buffer: *mut *mut AudioQueueBuffer,
    ) -> i32;
    fn AudioQueueSetProperty(
        queue: Queue,
        property_id: u32,
        data: *const c_void,
        data_size: u32,
    ) -> i32;
    fn AudioQueueEnqueueBuffer(
        queue: Queue,
        buffer: *mut AudioQueueBuffer,
        num_packet_descs: u32,
        packet_descs: *const AudioStreamPacketDescription,
    ) -> i32;
    fn AudioQueueStart(queue: Queue, start_time: *const c_void) -> i32;
    fn AudioQueueStop(queue: Queue, immediate: u8) -> i32;
    fn AudioQueueDispose(queue: Queue, immediate: u8) -> i32;
    fn AudioQueueSetParameter(queue: Queue, param_id: u32, value: f32) -> i32;
}

/// 全局 iOS AirPlay 音频转发开关（默认开启 `true`）
static AIRPLAY_AUDIO_ENABLED: AtomicBool = AtomicBool::new(true);

pub fn set_global_airplay_audio_enabled(enabled: bool) {
    AIRPLAY_AUDIO_ENABLED.store(enabled, Ordering::Release);
}

pub fn is_global_airplay_audio_enabled() -> bool {
    AIRPLAY_AUDIO_ENABLED.load(Ordering::Acquire)
}

struct BufferPool(Mutex<Vec<usize>>);

extern "C" fn on_buffer_recycle(user: *mut c_void, _queue: Queue, buffer: *mut AudioQueueBuffer) {
    if user.is_null() || buffer.is_null() {
        return;
    }
    let pool = unsafe { &*(user as *const BufferPool) };
    if let Ok(mut list) = pool.0.lock() {
        list.push(buffer as usize);
    }
}

/// 单个 AirPlay 会话的硬件音频解码与播放实例
pub struct AirPlayAudioDecoder {
    queue: Queue,
    pool: Box<BufferPool>,
    ct: u8,
    last_muted: bool,
}

unsafe impl Send for AirPlayAudioDecoder {}

impl AirPlayAudioDecoder {
    /// 根据协商的 AirPlay 压缩类型 (`ct`: 8=AAC-ELD, 4=AAC-LC, 2=ALAC) 创建 AudioQueue
    pub fn new(ct: u8, spf: u16) -> Result<Self, String> {
        let frames_per_packet = match (ct, spf) {
            (_, s) if s > 0 => s as u32,
            (8, _) => 480,
            (4, _) => 1024,
            (2, _) => 352,
            _ => return Err(format!("Unsupported AirPlay audio ct={ct}")),
        };

        let format_id = match ct {
            8 => u32::from_be_bytes(*b"aace"), // kAudioFormatMPEG4AAC_ELD
            4 => u32::from_be_bytes(*b"aac "), // kAudioFormatMPEG4AAC
            2 => u32::from_be_bytes(*b"alac"), // kAudioFormatAppleLossless
            _ => return Err(format!("Unsupported AirPlay audio ct={ct}")),
        };

        let asbd = AudioStreamBasicDescription {
            sample_rate: 44100.0,
            format_id,
            format_flags: 0,
            bytes_per_packet: 0,
            frames_per_packet,
            bytes_per_frame: 0,
            channels_per_frame: 2,
            bits_per_channel: 0,
            reserved: 0,
        };

        let mut decoder = Self {
            queue: ptr::null_mut(),
            pool: Box::new(BufferPool(Mutex::new(Vec::with_capacity(BUFFER_COUNT)))),
            ct,
            last_muted: !is_global_airplay_audio_enabled(),
        };

        unsafe {
            let status = AudioQueueNewOutput(
                &asbd,
                on_buffer_recycle,
                &*decoder.pool as *const BufferPool as *mut c_void,
                ptr::null_mut(),
                ptr::null_mut(),
                0,
                &mut decoder.queue,
            );
            if status != 0 || decoder.queue.is_null() {
                return Err(format!("AudioQueueNewOutput failed (status={status})"));
            }

            let cookie = Self::build_magic_cookie(ct, frames_per_packet);
            if !cookie.is_empty() {
                let _ = AudioQueueSetProperty(
                    decoder.queue,
                    K_AUDIO_QUEUE_PROPERTY_MAGIC_COOKIE,
                    cookie.as_ptr() as *const c_void,
                    cookie.len() as u32,
                );
            }

            for _ in 0..BUFFER_COUNT {
                let mut buf: *mut AudioQueueBuffer = ptr::null_mut();
                if AudioQueueAllocateBufferWithPacketDescriptions(
                    decoder.queue,
                    BUFFER_CAPACITY,
                    1,
                    &mut buf,
                ) != 0
                    || buf.is_null()
                {
                    return Err("AudioQueueAllocateBufferWithPacketDescriptions failed".into());
                }
                if let Ok(mut list) = decoder.pool.0.lock() {
                    list.push(buf as usize);
                }
            }

            let initial_vol = if decoder.last_muted { 0.0 } else { 1.0 };
            let _ = AudioQueueSetParameter(decoder.queue, K_AUDIO_QUEUE_PARAM_VOLUME, initial_vol);
            let _ = AudioQueueStart(decoder.queue, ptr::null());
        }

        Ok(decoder)
    }

    pub fn ct(&self) -> u8 {
        self.ct
    }

    /// 入队一帧解密后的 AirPlay 音频包
    pub fn enqueue(&mut self, packet: &[u8]) {
        if packet.is_empty() || packet.len() > BUFFER_CAPACITY as usize {
            return;
        }
        let muted = !is_global_airplay_audio_enabled();
        if muted != self.last_muted {
            self.last_muted = muted;
            unsafe {
                let _ = AudioQueueSetParameter(
                    self.queue,
                    K_AUDIO_QUEUE_PARAM_VOLUME,
                    if muted { 0.0 } else { 1.0 },
                );
            }
        }
        if muted {
            return;
        }

        let buf_addr = self.pool.0.lock().ok().and_then(|mut list| list.pop());
        let Some(addr) = buf_addr else {
            return;
        };
        let buf = addr as *mut AudioQueueBuffer;
        unsafe {
            ptr::copy_nonoverlapping(packet.as_ptr(), (*buf).data as *mut u8, packet.len());
            (*buf).size = packet.len() as u32;
            let desc = AudioStreamPacketDescription {
                start_offset: 0,
                variable_frames_in_packet: 0,
                data_byte_size: packet.len() as u32,
            };
            if !(*buf).packets.is_null() {
                *(*buf).packets = desc;
                (*buf).packet_count = 1;
            }
            if AudioQueueEnqueueBuffer(self.queue, buf, 1, &desc) == 0 {
                let _ = AudioQueueStart(self.queue, ptr::null());
            } else if let Ok(mut list) = self.pool.0.lock() {
                list.push(addr);
            }
        }
    }

    /// 构造 CoreAudio 解码所需的 ESDS / Magic Cookie
    fn build_magic_cookie(ct: u8, frames_per_packet: u32) -> Vec<u8> {
        match ct {
            // AAC-ELD 44100Hz 2ch 480spf: AudioSpecificConfig = [0xF8, 0xE8, 0x50, 0x00]
            8 => Self::wrap_esds(&[0xF8, 0xE8, 0x50, 0x00]),
            // AAC-LC 44100Hz 2ch 1024spf: AudioSpecificConfig = [0x12, 0x10]
            4 => Self::wrap_esds(&[0x12, 0x10]),
            // ALAC 24-byte Magic Cookie
            2 => {
                let mut cookie = Vec::with_capacity(24);
                cookie.extend_from_slice(&frames_per_packet.to_be_bytes());
                cookie.push(0); // compatibleVersion
                cookie.push(16); // bitDepth
                cookie.push(40); // pb
                cookie.push(10); // mb
                cookie.push(14); // kb
                cookie.push(2); // numChannels
                cookie.extend_from_slice(&255u16.to_be_bytes()); // maxRun
                cookie.extend_from_slice(&0u32.to_be_bytes()); // maxFrameBytes
                cookie.extend_from_slice(&0u32.to_be_bytes()); // avgBitRate
                cookie.extend_from_slice(&44100u32.to_be_bytes()); // sampleRate
                cookie
            }
            _ => Vec::new(),
        }
    }

    /// 将 AAC AudioSpecificConfig 封装为 CoreAudio 标准 MPEG-4 ES_Descriptor (ESDS)
    fn wrap_esds(asc: &[u8]) -> Vec<u8> {
        let dec_specific_len = asc.len();
        let dec_config_len = 13 + 2 + dec_specific_len;
        let es_descr_len = 3 + 2 + dec_config_len + 3;
        let mut out = Vec::with_capacity(2 + es_descr_len);
        // ES_Descriptor (tag 0x03)
        out.push(0x03);
        out.push(es_descr_len as u8);
        out.extend_from_slice(&[0x00, 0x00, 0x00]); // ES_ID = 0, flags = 0
        // DecoderConfigDescriptor (tag 0x04)
        out.push(0x04);
        out.push(dec_config_len as u8);
        out.push(0x40); // objectTypeIndication = 0x40 (Audio ISO/IEC 14496-3)
        out.push(0x15); // streamType = 0x05 (AudioStream) << 2 | 1
        out.extend_from_slice(&[0x00, 0x00, 0x00]); // bufferSizeDB
        out.extend_from_slice(&0u32.to_be_bytes()); // maxBitrate
        out.extend_from_slice(&0u32.to_be_bytes()); // avgBitrate
        // DecoderSpecificInfo (tag 0x05)
        out.push(0x05);
        out.push(dec_specific_len as u8);
        out.extend_from_slice(asc);
        // SLConfigDescriptor (tag 0x06)
        out.extend_from_slice(&[0x06, 0x01, 0x02]);
        out
    }
}

impl Drop for AirPlayAudioDecoder {
    fn drop(&mut self) {
        if !self.queue.is_null() {
            unsafe {
                let _ = AudioQueueStop(self.queue, 1);
                let _ = AudioQueueDispose(self.queue, 1);
            }
            self.queue = ptr::null_mut();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn airplay_audio_global_toggle_and_esds_builder() {
        set_global_airplay_audio_enabled(false);
        assert!(!is_global_airplay_audio_enabled());
        set_global_airplay_audio_enabled(true);
        assert!(is_global_airplay_audio_enabled());

        let eld_cookie = AirPlayAudioDecoder::build_magic_cookie(8, 480);
        assert!(eld_cookie.starts_with(&[0x03]));
        assert!(eld_cookie.windows(4).any(|w| w == [0xF8, 0xE8, 0x50, 0x00]));

        let alac_cookie = AirPlayAudioDecoder::build_magic_cookie(2, 352);
        assert_eq!(alac_cookie.len(), 24);
    }
}
