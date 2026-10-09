//! UxPlay 协议核心与 AnyDeck VideoToolbox 的接入边界。
//! C 线程回调只借用输入；stop join 完成后才释放 Rust 上下文。

use super::{AirPlayServer, AirPlayStatus};
use crate::video::{Decoder, Frame};
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::os::unix::fs::PermissionsExt;
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::{Arc, Mutex};

extern "C" {
    fn anydeck_uxplay_start(
        name: *const c_char,
        mac: *const c_char,
        keyfile: *const c_char,
        port: u16,
        publish: bool,
        context: *mut c_void,
        video: extern "C" fn(*mut c_void, *const u8, c_int, u64),
        reset: extern "C" fn(*mut c_void),
        log: extern "C" fn(*mut c_void, c_int, *const c_char),
    ) -> *mut c_void;
    fn anydeck_uxplay_stop(handle: *mut c_void);
    fn anydeck_uxplay_port(handle: *mut c_void) -> u16;
}

/// 回调上下文，避免引用环
struct Context {
    status: Arc<AtomicU8>,
    error: Arc<Mutex<String>>,
    frame: Arc<Frame>,
    decoder: Mutex<Decoder>,
}

pub(super) struct Receiver {
    native: *mut c_void,
    _context: Box<Context>,
    pub port: u16,
}

// native 句柄只在持有 Server.native 锁时启动/停止；回调数据使用 Arc/Mutex。
unsafe impl Send for Receiver {}

impl Receiver {
    pub fn start(server: &Arc<AirPlayServer>, name: &str, port: u16) -> Result<Self, String> {
        let base = std::env::var_os("HOME").ok_or("HOME unavailable for AirPlay identity")?;
        let directory = std::path::PathBuf::from(base).join("Library/Application Support/com.github.anydeck/airplay");
        std::fs::create_dir_all(&directory).map_err(|e| e.to_string())?;
        std::fs::set_permissions(&directory, std::fs::Permissions::from_mode(0o700)).map_err(|e| e.to_string())?;
        let keyfile = directory.join("receiver.pem");
        let receiver = Self::start_with_identity(server, name, port, &keyfile, true)?;
        std::fs::set_permissions(&keyfile, std::fs::Permissions::from_mode(0o600)).map_err(|e| e.to_string())?;
        Ok(receiver)
    }

    fn start_with_identity(
        server: &Arc<AirPlayServer>,
        name: &str,
        port: u16,
        keyfile: &std::path::Path,
        publish: bool,
    ) -> Result<Self, String> {
        let mut context = Box::new(Context {
            status: server.status.clone(),
            error: server.last_error.clone(),
            frame: server.frame.clone(),
            decoder: Mutex::new(Decoder::new(server.frame.clone())),
        });

        let name_c = CString::new(name).map_err(|e| e.to_string())?;
        let mac = AirPlayServer::get_local_mac();
        let mac_c = CString::new(mac).map_err(|e| e.to_string())?;
        let keyfile_str = keyfile.to_string_lossy();
        let keyfile_c = CString::new(keyfile_str.as_ref()).map_err(|e| e.to_string())?;

        let ctx_ptr = &mut *context as *mut Context as *mut c_void;
        let handle = unsafe {
            anydeck_uxplay_start(
                name_c.as_ptr(),
                mac_c.as_ptr(),
                keyfile_c.as_ptr(),
                port,
                publish,
                ctx_ptr,
                Self::on_video_data,
                Self::on_stream_reset,
                Self::on_log_message,
            )
        };

        if handle.is_null() {
            let detail = server.last_error.lock().map(|e| e.clone()).unwrap_or_default();
            return Err(format!("UxPlay failed to start AirPlay server: {detail}"));
        }

        let actual_port = unsafe { anydeck_uxplay_port(handle) };
        Ok(Self {
            native: handle,
            _context: context,
            port: actual_port,
        })
    }

    /// C 回调不得向外 unwind；解码与重置串行，只有有效 IOSurface 才报告 Mirroring。
    extern "C" fn on_video_data(ctx: *mut c_void, data: *const u8, len: c_int, pts: u64) {
        if ctx.is_null() || data.is_null() || len <= 0 || len > 10 * 1024 * 1024 { return; }
        let _ = std::panic::catch_unwind(|| {
            let context = unsafe { &*(ctx as *const Context) };
            let Ok(mut decoder) = context.decoder.lock() else { return; };
            if context.status.load(Ordering::Acquire) == AirPlayStatus::Stopped as u8 { return; }
            let slice = unsafe { std::slice::from_raw_parts(data, len as usize) };
            if let Err(error) = decoder.decode(slice, pts) {
                context.record_error(format!("VideoToolbox decode failed: {error}"));
                return;
            }
            if context.frame.has_surface() && context.status.compare_exchange(
                AirPlayStatus::Idle as u8, AirPlayStatus::Mirroring as u8,
                Ordering::AcqRel, Ordering::Acquire).is_ok() {
                eprintln!("[AirPlay UxPlay] First decoded IOSurface ready");
            }
        });
    }

    extern "C" fn on_stream_reset(ctx: *mut c_void) {
        if ctx.is_null() { return; }
        let _ = std::panic::catch_unwind(|| {
            let context = unsafe { &*(ctx as *const Context) };
            if let Ok(mut decoder) = context.decoder.lock() {
                // 重新创建同时清除 SPS/PPS；等旧解码回调完成后再清除帧。
                *decoder = Decoder::new(context.frame.clone());
                context.frame.clear();
                let _ = context.status.compare_exchange(
                    AirPlayStatus::Mirroring as u8, AirPlayStatus::Idle as u8,
                    Ordering::AcqRel, Ordering::Acquire);
            }
        });
    }

    extern "C" fn on_log_message(ctx: *mut c_void, level: c_int, msg: *const c_char) {
        if ctx.is_null() || msg.is_null() { return; }
        let _ = std::panic::catch_unwind(|| {
            let context = unsafe { &*(ctx as *const Context) };
            let text = unsafe { CStr::from_ptr(msg).to_string_lossy() };
            if level <= 4 {
                context.record_error(format!("UxPlay: {text}"));
            } else if level <= 6 {
                eprintln!("[UxPlay] {text}");
            }
        });
    }

}

impl Drop for Receiver {
    fn drop(&mut self) {
        if !self.native.is_null() {
            unsafe {
                anydeck_uxplay_stop(self.native);
            }
            self.native = std::ptr::null_mut();
        }
    }
}

impl Context {
    fn record_error(&self, error: String) {
        if let Ok(mut latest) = self.error.lock() {
            let bounded: String = error.chars().take(512).collect();
            if *latest != bounded { eprintln!("[AirPlay] {bounded}"); }
            *latest = bounded;
        }
    }
}

#[cfg(test)]
#[path = "uxplay_tests.rs"]
mod tests;
