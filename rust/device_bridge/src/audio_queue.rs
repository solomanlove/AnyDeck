//! macOS AudioQueue 的最小 Rust 绑定。只有音频工作线程访问 Queue；回调回收固定池。
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

// 原始指针只作为 Queue 已分配 buffer 的地址保存；不会在锁外并发读写 buffer。
struct Pool(Mutex<Vec<usize>>);
extern "C" fn recycle(user: *mut c_void, _queue: Queue, buffer: *mut Buffer) {
    let pool = unsafe { &*(user as *const Pool) };
    if let Ok(mut buffers) = pool.0.lock() {
        buffers.push(buffer as usize);
    }
}

const BUFFER_CAPACITY: u32 = 16384;
const BUFFER_COUNT: usize = 8;

pub struct Player {
    queue: Queue,
    pool: Box<Pool>,
}
impl Player {
    pub fn new() -> Result<Self, String> {
        let mut player = Self {
            queue: ptr::null_mut(),
            pool: Box::new(Pool(Mutex::new(Vec::with_capacity(BUFFER_COUNT)))),
        };
        let format = Format {
            sample_rate: 48000.0,
            format_id: u32::from_be_bytes(*b"lpcm"),
            flags: 12,
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
            for _ in 0..BUFFER_COUNT {
                let mut buffer = ptr::null_mut();
                if AudioQueueAllocateBuffer(player.queue, BUFFER_CAPACITY, &mut buffer) != 0
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

    /// 写入 PCM 数据块，支持 4096、3840 等任意大小（自适应分块与入队）。
    pub fn write(&mut self, pcm: &[u8]) -> Result<(), String> {
        if pcm.is_empty() {
            return Ok(());
        }
        // 保证按 16-bit 双声道采样（每帧 4 字节）对齐截断
        let valid_len = pcm.len() - (pcm.len() % 4);
        if valid_len == 0 {
            return Ok(());
        }
        let data = &pcm[..valid_len];

        for chunk in data.chunks(BUFFER_CAPACITY as usize) {
            let address = self.pool.0.lock().map_err(|_| "Audio pool poisoned")?.pop();
            if let Some(address) = address {
                let buffer = address as *mut Buffer;
                unsafe {
                    ptr::copy_nonoverlapping(chunk.as_ptr(), (*buffer).data as *mut u8, chunk.len());
                    (*buffer).size = chunk.len() as u32;
                    if AudioQueueEnqueueBuffer(self.queue, buffer, 0, ptr::null()) != 0 {
                        return Err("Audio enqueue failed".into());
                    }
                    // 确保 AudioQueue 在饥饿停顿后及时恢复播放
                    let _ = AudioQueueStart(self.queue, ptr::null());
                }
            }
        }
        Ok(())
    }
}
impl Drop for Player {
    fn drop(&mut self) {
        // 不持有 pool 锁：Dispose 同步等待全部回调结束后再释放 Box，避免死锁/UAF。
        if !self.queue.is_null() {
            unsafe {
                AudioQueueStop(self.queue, 1);
                AudioQueueDispose(self.queue, 1);
            }
        }
    }
}
