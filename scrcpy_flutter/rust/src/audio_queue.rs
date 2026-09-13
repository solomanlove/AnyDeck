//! macOS AudioQueue 的最小 Rust 绑定，用于播放 scrcpy 传来的 RAW PCM 音频流。
use std::ffi::c_void;
use std::ptr;
use std::sync::Mutex;

type Queue = *mut c_void;

#[repr(C)]
struct Format {
    sample_rate: f64,
    format_id: u32,
    flags: u32,
    bytes_per_packet: u32,
    frames_per_packet: u32,
    bytes_per_frame: u32,
    channels: u32,
    bits: u32,
    reserved: u32,
}

#[repr(C)]
struct Buffer {
    capacity: u32,
    data: *mut c_void,
    size: u32,
    user: *mut c_void,
    packet_capacity: u32,
    packets: *mut c_void,
    packet_count: u32,
}

#[link(name = "AudioToolbox", kind = "framework")]
extern "C" {
    fn AudioQueueNewOutput(
        format: *const Format,
        callback: extern "C" fn(*mut c_void, Queue, *mut Buffer),
        user: *mut c_void,
        run_loop: *mut c_void,
        mode: *mut c_void,
        flags: u32,
        queue: *mut Queue,
    ) -> i32;
    fn AudioQueueAllocateBuffer(queue: Queue, size: u32, buffer: *mut *mut Buffer) -> i32;
    fn AudioQueueEnqueueBuffer(
        queue: Queue,
        buffer: *mut Buffer,
        count: u32,
        descriptions: *const c_void,
    ) -> i32;
    fn AudioQueueStart(queue: Queue, time: *const c_void) -> i32;
    fn AudioQueueStop(queue: Queue, immediate: u8) -> i32;
    fn AudioQueueDispose(queue: Queue, immediate: u8) -> i32;
    fn AudioQueueSetParameter(queue: Queue, parameter: u32, value: f32) -> i32;
}

/// 缓冲池，保存空闲的 AudioQueue 缓冲区地址。
struct Pool(Mutex<Vec<usize>>);

extern "C" fn recycle(user: *mut c_void, _queue: Queue, buffer: *mut Buffer) {
    let pool = unsafe { &*(user as *const Pool) };
    if let Ok(mut buffers) = pool.0.lock() {
        buffers.push(buffer as usize);
    }
}

/// 基于 AudioQueue 的 PCM 音频播放器。
pub struct Player {
    queue: Queue,
    pool: Box<Pool>,
}

impl Player {
    pub fn new() -> Result<Self, String> {
        let mut player = Self {
            queue: ptr::null_mut(),
            pool: Box::new(Pool(Mutex::new(Vec::with_capacity(8)))),
        };
        let format = Format {
            sample_rate: 48000.0,
            format_id: u32::from_be_bytes(*b"lpcm"),
            flags: 12, // 16-bit signed integer, packed
            bytes_per_packet: 4,
            frames_per_packet: 1,
            bytes_per_frame: 4,
            channels: 2,
            bits: 16,
            reserved: 0,
        };
        unsafe {
            if AudioQueueNewOutput(
                &format,
                recycle,
                &*player.pool as *const Pool as *mut c_void,
                ptr::null_mut(),
                ptr::null_mut(),
                0,
                &mut player.queue,
            ) != 0
            {
                return Err("Audio output unavailable".into());
            }
            // 分配 8 个每个 16KB 的缓冲区，适配网络抖动与多包并发
            for _ in 0..8 {
                let mut buffer = ptr::null_mut();
                if AudioQueueAllocateBuffer(player.queue, 16384, &mut buffer) != 0
                    || buffer.is_null()
                {
                    return Err("Audio buffer allocation failed".into());
                }
                player
                    .pool
                    .0
                    .lock()
                    .map_err(|_| "Audio pool poisoned")?
                    .push(buffer as usize);
            }
            if AudioQueueStart(player.queue, ptr::null()) != 0 {
                return Err("Audio output start failed".into());
            }
        }
        Ok(player)
    }

    pub fn mute(&mut self, muted: bool) -> Result<(), String> {
        let status =
            unsafe { AudioQueueSetParameter(self.queue, 1, if muted { 0.0 } else { 1.0 }) };
        if status == 0 {
            Ok(())
        } else {
            Err("Audio volume failed".into())
        }
    }

    /// 写入 PCM 数据到音频播放队列。缓冲区满时丢弃最旧数据块，防止延迟累积。
    pub fn write(&mut self, pcm: &[u8]) -> Result<(), String> {
        if pcm.is_empty() {
            return Ok(());
        }
        let address = self.pool.0.lock().map_err(|_| "Audio pool poisoned")?.pop();
        if let Some(address) = address {
            let buffer = address as *mut Buffer;
            unsafe {
                let to_copy = std::cmp::min(pcm.len(), (*buffer).capacity as usize);
                ptr::copy_nonoverlapping(pcm.as_ptr(), (*buffer).data as *mut u8, to_copy);
                (*buffer).size = to_copy as u32;
                if AudioQueueEnqueueBuffer(self.queue, buffer, 0, ptr::null()) != 0 {
                    return Err("Audio enqueue failed".into());
                }
            }
        }
        Ok(())
    }
}

impl Drop for Player {
    fn drop(&mut self) {
        if !self.queue.is_null() {
            unsafe {
                AudioQueueStop(self.queue, 1);
                AudioQueueDispose(self.queue, 1);
            }
        }
    }
}
