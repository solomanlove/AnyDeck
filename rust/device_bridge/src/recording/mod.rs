//! 独立电脑录制会话与 C ABI；生命周期接口沿用现有窗口句柄跟踪。
mod muxer;
mod protocol;
mod receiver;
#[cfg(test)]
mod tests;

use std::{
    collections::HashMap,
    ffi::{c_char, CStr},
    net::{Shutdown, TcpStream},
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, AtomicU8, Ordering},
        Arc, Mutex, OnceLock,
    },
};

pub(super) struct Recording {
    serial: String,
    stopped: AtomicBool,
    status: AtomicU8,
    sockets: Mutex<Vec<TcpStream>>,
    error: Mutex<String>,
}
static RECORDINGS: OnceLock<Mutex<HashMap<u64, Arc<Recording>>>> = OnceLock::new();
fn registry() -> &'static Mutex<HashMap<u64, Arc<Recording>>> {
    RECORDINGS.get_or_init(|| Mutex::new(HashMap::new()))
}
fn get(id: u64) -> Option<Arc<Recording>> {
    registry().lock().ok()?.get(&id).cloned()
}
impl Recording {
    fn cancel(&self) {
        self.stopped.store(true, Ordering::Release);
        if let Ok(sockets) = self.sockets.lock() {
            for socket in sockets.iter() {
                let _ = socket.shutdown(Shutdown::Both);
            }
        }
    }
    fn fail(&self, error: String) {
        if let Ok(mut value) = self.error.lock() {
            if value.is_empty() {
                *value = error.chars().take(1024).collect();
            }
        }
        self.cancel();
    }
    fn error(&self) -> String {
        self.error
            .lock()
            .map(|s| s.clone())
            .unwrap_or_else(|_| "Recording lock poisoned".into())
    }
}

/// 启动无窗口 H.264/AAC 录制；返回的句柄支持 anydeck_status/stop/release。
/// # Safety
/// 四个参数须为调用期间有效的 NUL 结尾 UTF-8 字符串。
#[no_mangle]
pub unsafe extern "C" fn anydeck_start_recording(
    adb: *const c_char,
    serial: *const c_char,
    jar: *const c_char,
    path: *const c_char,
) -> u64 {
    let pointers = [adb, serial, jar, path];
    if pointers.iter().any(|p| p.is_null()) {
        return 0;
    }
    let values = pointers.map(|p| CStr::from_ptr(p).to_str().map(str::to_owned));
    let [Ok(adb), Ok(serial), Ok(jar), Ok(path)] = values else {
        return 0;
    };
    if adb.is_empty()
        || serial.is_empty()
        || serial.starts_with('-')
        || jar.is_empty()
        || path.is_empty()
    {
        return 0;
    }
    let id = crate::NEXT_ID.fetch_add(1, Ordering::Relaxed);
    let current = Arc::new(Recording {
        serial: serial.clone(),
        stopped: AtomicBool::new(false),
        status: AtomicU8::new(0),
        sockets: Mutex::new(vec![]),
        error: Mutex::new(String::new()),
    });
    let Ok(mut map) = registry().lock() else {
        return 0;
    };
    if map
        .values()
        .any(|s| s.serial == serial && s.status.load(Ordering::Acquire) < 2)
    {
        return 0;
    }
    map.insert(id, current.clone());
    drop(map);
    if std::thread::Builder::new()
        .name(format!("anydeck-record-{id}"))
        .spawn(move || {
            let result = std::panic::catch_unwind(|| {
                receiver::run(adb, serial, jar, PathBuf::from(path), id, &current)
            });
            match result {
                Ok(Ok(())) => {}
                Ok(Err(error)) => {
                    current.cancel();
                    if let Ok(mut detail) = current.error.lock() {
                        *detail = error.chars().take(1024).collect();
                    }
                }
                Err(_) => current.fail("Recording worker panicked".into()),
            }
            // run 返回前已写完 MP4、join 收包线程并释放 ADB Transport。
            current.status.store(
                if current.error().is_empty() { 2 } else { 3 },
                Ordering::Release,
            );
        })
        .is_err()
    {
        if let Ok(mut map) = registry().lock() {
            map.remove(&id);
        }
        return 0;
    }
    id
}

pub fn status(id: u64) -> Option<u8> {
    get(id).map(|s| s.status.load(Ordering::Acquire))
}
pub fn stop(id: u64) {
    if let Some(s) = get(id) {
        s.cancel();
    }
}
pub fn release(id: u64) {
    stop(id);
    if let Ok(mut map) = registry().lock() {
        map.remove(&id);
    }
}

/// 返回完整 UTF-8 错误长度；仅在调用方容量足够时拷贝，避免截断多字节字符。
/// # Safety
/// 非空 out 必须指向 capacity 字节的可写内存。
#[no_mangle]
pub unsafe extern "C" fn anydeck_recording_error(id: u64, out: *mut u8, capacity: usize) -> usize {
    let error = get(id).map(|s| s.error()).unwrap_or_default();
    if !out.is_null() && capacity >= error.len() {
        std::ptr::copy_nonoverlapping(error.as_ptr(), out, error.len());
    }
    error.len()
}
