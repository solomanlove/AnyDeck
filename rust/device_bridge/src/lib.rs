//! 三个功能共用的 Rust 会话核心：ADB、协议、解码/播放、剪贴板与资源回收。
mod adb;
mod adb_socket;
mod audio_queue;
pub mod performance;
pub mod core;
pub mod c_api_ios;
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
    pub(crate) stopped: AtomicBool,
    pub(crate) muted: AtomicBool,
    pub(crate) refresh: AtomicBool,
    pub(crate) status: AtomicU8,
    pub(crate) revision: AtomicU64,
    pub(crate) clipboard: Mutex<Vec<u8>>,
    pub(crate) socket: Mutex<Option<TcpStream>>,
    pub(crate) control_socket: Mutex<Option<TcpStream>>,
    pub(crate) frame: Arc<video::Frame>,
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
        control_socket: Mutex::new(None),
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
            let res = std::panic::catch_unwind(|| worker::run(adb, serial, jar, kind, id, &current));
            if let Err(e) = &res {
                eprintln!("[RustDeviceBridge] worker::run PANIC: {:?}", e);
            } else if let Ok(Err(err)) = &res {
                eprintln!("[RustDeviceBridge] worker::run ERR: {}", err);
            }
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

/// 启动屏幕投屏会话（连接 video、audio、control，解码输出至 Texture）。
///
/// # Safety
/// host 必须指向以 NUL 结尾的有效 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn anydeck_start_mirror(
    host: *const c_char,
    port: i32,
    audio_enabled: u8,
) -> u64 {
    if host.is_null() || port <= 0 || port > 65535 {
        return 0;
    }
    let Ok(host) = CStr::from_ptr(host).to_str().map(str::to_owned) else {
        return 0;
    };
    let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
    let current = Arc::new(Session {
        stopped: AtomicBool::new(false),
        muted: AtomicBool::new(false),
        refresh: AtomicBool::new(true),
        status: AtomicU8::new(0),
        revision: AtomicU64::new(0),
        clipboard: Mutex::new(Vec::new()),
        socket: Mutex::new(None),
        control_socket: Mutex::new(None),
        frame: Arc::new(video::Frame::default()),
    });
    let Ok(mut registry) = sessions().lock() else {
        return 0;
    };
    registry.insert(id, current.clone());
    drop(registry);

    let session_clone = current.clone();
    let audio_on = audio_enabled != 0;
    let port_u16 = port as u16;
    if std::thread::Builder::new()
        .name(format!("anydeck-mirror-{}", id))
        .spawn(move || {
            let _ = std::panic::catch_unwind(|| {
                worker::run_mirror(host, port_u16, audio_on, id, &session_clone)
            });
            session_clone.status.store(
                if session_clone.stopped.load(Ordering::Acquire) {
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

/// 向设备的 control socket 发送二进制控制指令。
///
/// # Safety
/// bytes 必须指向至少 len 字节的有效内存区。
#[no_mangle]
pub unsafe extern "C" fn anydeck_send_control(
    id: u64,
    bytes: *const u8,
    len: usize,
) -> bool {
    if bytes.is_null() || len == 0 {
        return false;
    }
    let Some(s) = session(id) else {
        return false;
    };
    if s.stopped.load(Ordering::Acquire) {
        return false;
    }
    let data = std::slice::from_raw_parts(bytes, len);
    if let Ok(mut guard) = s.control_socket.lock() {
        if let Some(stream) = guard.as_mut() {
            use std::io::Write;
            if stream.write_all(data).is_ok() {
                let _ = stream.flush();
                return true;
            }
        }
    }
    false
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
/// 检查当前解码帧是否已绑定 IOSurface（确保 Metal Texture 可用）。
#[no_mangle]
pub extern "C" fn anydeck_has_surface(id: u64) -> bool {
    session(id).map(|s| s.frame.has_surface()).unwrap_or(false)
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
        if let Ok(socket) = s.control_socket.lock() {
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

/// 零拷贝轮询指定设备的性能指标快照
///
/// # Safety
/// serial 与 out_snapshot 必须为非空且合法的指针。
#[no_mangle]
pub unsafe extern "C" fn anydeck_poll_performance(
    serial: *const c_char,
    out_snapshot: *mut performance::PerformanceSnapshotFFI,
) -> bool {
    if serial.is_null() || out_snapshot.is_null() {
        return false;
    }
    let Ok(serial_str) = CStr::from_ptr(serial).to_str() else {
        return false;
    };
    if serial_str.is_empty() {
        return false;
    }
    performance::poll_device_performance(serial_str, &mut *out_snapshot).is_ok()
}

/// 清除指定设备的性能采样历史状态
///
/// # Safety
/// serial 必须为有效的 NUL 结尾 C 字符串指针。
#[no_mangle]
pub unsafe extern "C" fn anydeck_clear_performance_cache(serial: *const c_char) {
    if serial.is_null() {
        return;
    }
    if let Ok(serial_str) = CStr::from_ptr(serial).to_str() {
        performance::clear_device_cache(serial_str);
    }
}

/// 批量并发执行控制台 Shell 命令 (带 USB 总线信号量并发保护)
///
/// # Safety
/// serials_json 与 command 必须为有效的 NUL 结尾 C 字符串指针。
/// 返回指针指向的堆内存必须由调用方通过 `anydeck_free_string` 释放。
#[no_mangle]
pub unsafe extern "C" fn anydeck_batch_execute_shell(
    platform: u8,
    serials_json: *const c_char,
    command: *const c_char,
    max_concurrency: u32,
) -> *mut c_char {
    if serials_json.is_null() || command.is_null() {
        return std::ptr::null_mut();
    }
    let (Ok(serials_str), Ok(cmd_str)) = (
        CStr::from_ptr(serials_json).to_str(),
        CStr::from_ptr(command).to_str(),
    ) else {
        return std::ptr::null_mut();
    };

    let serials: Vec<String> = match serde_json::from_str(serials_str) {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let target_platform = core::DevicePlatform::from_u8(platform).unwrap_or(core::DevicePlatform::Android);

    let drivers: Vec<Arc<dyn core::DeviceDriver>> = serials
        .into_iter()
        .map(|s| match target_platform {
            core::DevicePlatform::Android => Arc::new(core::AndroidDriver::new(s)) as Arc<dyn core::DeviceDriver>,
            core::DevicePlatform::Harmony => Arc::new(core::HarmonyDriver::new(s)) as Arc<dyn core::DeviceDriver>,
            core::DevicePlatform::Ios => Arc::new(core::IosDriver::new(s)) as Arc<dyn core::DeviceDriver>,
        })
        .collect();

    let results = core::BatchManager::execute_shell_batch_blocking(
        drivers,
        cmd_str.to_string(),
        max_concurrency as usize,
    );

    let json_bytes = match serde_json::to_string(&results) {
        Ok(j) => j,
        Err(_) => return std::ptr::null_mut(),
    };

    std::ffi::CString::new(json_bytes)
        .map(|cs| cs.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// 查询已连接的鸿蒙设备列表，返回 JSON 字符串裸指针
///
/// # Safety
/// 返回指针指向的堆内存必须由调用方通过 `anydeck_free_string` 释放。
#[no_mangle]
pub unsafe extern "C" fn anydeck_harmony_list_devices() -> *mut c_char {
    let result = core::BatchManager::runtime().block_on(async {
        core::HarmonyDriver::list_targets().await
    });

    let json_bytes = match result {
        Ok(targets) => serde_json::to_string(&targets).unwrap_or_else(|_| "[]".into()),
        Err(_) => "[]".into(),
    };

    std::ffi::CString::new(json_bytes)
        .map(|cs| cs.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// 通过统一 DAL 设备驱动执行单个设备 Shell 命令
///
/// # Safety
/// serial 与 command 必须为有效的 NUL 结尾 C 字符串指针。
/// 返回指针指向的堆内存必须由调用方通过 `anydeck_free_string` 释放。
#[no_mangle]
pub unsafe extern "C" fn anydeck_dal_execute_shell(
    platform: u8,
    serial: *const c_char,
    command: *const c_char,
) -> *mut c_char {
    if serial.is_null() || command.is_null() {
        return std::ptr::null_mut();
    }
    let (Ok(serial_str), Ok(cmd_str)) = (
        CStr::from_ptr(serial).to_str(),
        CStr::from_ptr(command).to_str(),
    ) else {
        return std::ptr::null_mut();
    };

    let driver: Arc<dyn core::DeviceDriver> = match core::DevicePlatform::from_u8(platform) {
        Some(core::DevicePlatform::Android) => Arc::new(core::AndroidDriver::new(serial_str)),
        Some(core::DevicePlatform::Harmony) => Arc::new(core::HarmonyDriver::new(serial_str)),
        Some(core::DevicePlatform::Ios) => Arc::new(core::IosDriver::new(serial_str)),
        None => return std::ptr::null_mut(),
    };

    let result = core::BatchManager::runtime().block_on(async {
        driver.execute_shell(cmd_str).await
    });

    let (success, payload) = match result {
        Ok(out) => (true, out),
        Err(err) => (false, err),
    };

    let response = serde_json::json!({
        "success": success,
        "payload": payload,
    });

    let json_str = response.to_string();
    std::ffi::CString::new(json_str)
        .map(|cs| cs.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// 释放由 Rust 原生层分配并返回给 Dart 侧的 C 字符串裸指针
///
/// # Safety
/// ptr 必须是由 `CString::into_raw` 生成的指针或 null。
#[no_mangle]
pub unsafe extern "C" fn anydeck_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(std::ffi::CString::from_raw(ptr));
    }
}

