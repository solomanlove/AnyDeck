//! 三个功能共用的 Rust 会话核心：ADB、协议、解码/播放、剪贴板与资源回收。
mod adb;
mod audio_queue;
mod stream;
mod video;
mod video_ffi;
mod worker;

use std::collections::HashMap;
use std::ffi::{c_char, c_void, CStr};
use std::net::{Shutdown, TcpStream};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicU8, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

pub(crate) struct Session {
    stopped: AtomicBool,
    muted: AtomicBool,
    refresh: AtomicBool,
    status: AtomicU8,
    revision: AtomicU64,
    clipboard: Mutex<Vec<u8>>,
    socket: Mutex<Option<TcpStream>>,
    frame: Arc<video::Frame>,
}
static SESSIONS: OnceLock<Mutex<HashMap<u64, Arc<Session>>>> = OnceLock::new();
static NEXT_ID: AtomicU64 = AtomicU64::new(1);
fn sessions() -> &'static Mutex<HashMap<u64, Arc<Session>>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}
fn session(id: u64) -> Option<Arc<Session>> {
    sessions().lock().ok()?.get(&id).cloned()
}

/// kind: 0 后摄、1 麦克风、2 剪贴板、3 前摄。
///
/// # Safety
/// 三个非空指针必须指向调用期间有效的 NUL 结尾 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn anydeck_start(
    adb: *const c_char,
    serial: *const c_char,
    jar: *const c_char,
    kind: u8,
) -> u64 {
    if adb.is_null() || serial.is_null() || jar.is_null() || kind > 3 {
        return 0;
    }
    let strings = [adb, serial, jar].map(|ptr| CStr::from_ptr(ptr).to_str().map(str::to_owned));
    let [Ok(adb), Ok(serial), Ok(jar)] = strings else {
        return 0;
    };
    // serial 始终作为参数传给 adb，不能充当命令行选项。
    if adb.is_empty() || serial.is_empty() || serial.starts_with('-') || jar.is_empty() {
        return 0;
    }
    let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
    let current = Arc::new(Session {
        stopped: AtomicBool::new(false),
        muted: AtomicBool::new(false),
        refresh: AtomicBool::new(true),
        status: AtomicU8::new(0),
        revision: AtomicU64::new(0),
        clipboard: Mutex::new(Vec::new()),
        socket: Mutex::new(None),
        frame: Arc::new(video::Frame::default()),
    });
    let Ok(mut registry) = sessions().lock() else {
        return 0;
    };
    registry.insert(id, current.clone());
    drop(registry);
    if std::thread::Builder::new()
        .name("anydeck-device-session".into())
        .spawn(move || {
            let _ = std::panic::catch_unwind(|| worker::run(adb, serial, jar, kind, id, &current));
            current.status.store(
                if current.stopped.load(Ordering::Acquire) {
                    2
                } else {
                    3
                },
                Ordering::Release,
            );
        })
        .is_err()
    {
        if let Ok(mut registry) = sessions().lock() {
            registry.remove(&id);
        }
        return 0;
    }
    id
}

/// 状态：0 启动中、1 运行、2 已停止、3 失败。查询不阻塞 UI。
#[no_mangle]
pub extern "C" fn anydeck_status(id: u64) -> u8 {
    session(id)
        .map(|s| s.status.load(Ordering::Acquire))
        .unwrap_or(2)
}
#[no_mangle]
pub extern "C" fn anydeck_mute(id: u64, muted: u8) {
    if let Some(s) = session(id) {
        s.muted.store(muted != 0, Ordering::Release);
    }
}
#[no_mangle]
pub extern "C" fn anydeck_refresh(id: u64) {
    if let Some(s) = session(id) {
        s.refresh.store(true, Ordering::Release);
    }
}
#[no_mangle]
pub extern "C" fn anydeck_revision(id: u64) -> u64 {
    session(id)
        .map(|s| s.revision.load(Ordering::Acquire))
        .unwrap_or(0)
}
/// 返回长度；容量不足时不拷贝。剪贴板最大 256KiB，Flutter 使用固定上限读取。
///
/// # Safety
/// output 非空时必须指向至少 capacity 字节的独占可写缓冲区。
#[no_mangle]
pub unsafe extern "C" fn anydeck_clipboard(id: u64, output: *mut u8, capacity: usize) -> usize {
    let Some(s) = session(id) else {
        return 0;
    };
    let Ok(text) = s.clipboard.lock() else {
        return 0;
    };
    if !output.is_null() && capacity >= text.len() {
        std::ptr::copy_nonoverlapping(text.as_ptr(), output, text.len());
    }
    text.len()
}
#[no_mangle]
pub extern "C" fn anydeck_video_size(id: u64) -> u64 {
    let Some(s) = session(id) else {
        return 0;
    };
    let (width, height) = s.frame.dimensions();
    ((width as u64) << 32) | height as u64
}
/// 返回 retain 后的 CVPixelBuffer，由 Flutter Texture 协议接管 release。
#[no_mangle]
pub extern "C" fn anydeck_copy_pixel_buffer(id: u64) -> *mut c_void {
    session(id)
        .map(|s| s.frame.copy())
        .unwrap_or(std::ptr::null_mut())
}
/// 停止只发信号和关闭 socket；状态变为 2 时 ADB 与原生资源已清理完成。
#[no_mangle]
pub extern "C" fn anydeck_stop(id: u64) {
    if let Some(s) = session(id) {
        s.stopped.store(true, Ordering::Release);
        if let Ok(socket) = s.socket.lock() {
            if let Some(socket) = socket.as_ref() {
                let _ = socket.shutdown(Shutdown::Both);
            }
        }
    }
}
/// Flutter 在停止完成后释放句柄；重复调用安全。
#[no_mangle]
pub extern "C" fn anydeck_release(id: u64) {
    anydeck_stop(id);
    if let Ok(mut registry) = sessions().lock() {
        registry.remove(&id);
    }
}
/// FFI 字符串/结果缓冲区的对称分配，不引入额外 Dart 或 Rust 依赖。
#[no_mangle]
pub extern "C" fn anydeck_alloc(size: usize) -> *mut u8 {
    if size == 0 || size > 1024 * 1024 {
        return std::ptr::null_mut();
    }
    Box::into_raw(vec![0u8; size].into_boxed_slice()) as *mut u8
}
/// 释放 anydeck_alloc 返回的缓冲区。
///
/// # Safety
/// pointer 与 size 必须对应一次尚未释放的 anydeck_alloc 调用，不可重复释放。
#[no_mangle]
pub unsafe extern "C" fn anydeck_free(pointer: *mut u8, size: usize) {
    if !pointer.is_null() && size > 0 {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
            pointer, size,
        )));
    }
}
