//! UxPlay 协议核心与 AnyDeck VideoToolbox 的接入边界。
//! C 线程回调只借用输入；stop join 完成后才释放 Rust 上下文。

use super::audio::AirPlayAudioDecoder;
use super::{AirPlayServer, AirPlayStatus};
use crate::video::{Decoder, Frame};
use std::collections::HashMap;
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::os::unix::fs::PermissionsExt;
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

extern "C" {
    fn anydeck_uxplay_start(
        name: *const c_char,
        mac: *const c_char,
        keyfile: *const c_char,
        port: u16,
        publish: bool,
        context: *mut c_void,
        video: extern "C" fn(*mut c_void, *const u8, c_int, u64),
        audio: extern "C" fn(*mut c_void, *const u8, c_int, u8, u16),
        reset: extern "C" fn(*mut c_void),
        log: extern "C" fn(*mut c_void, c_int, *const c_char),
        client: extern "C" fn(*mut c_void, *const c_char, *const c_char, *const c_char) -> *mut c_void,
        detach: extern "C" fn(*mut c_void, *mut c_void),
        media_command: extern "C" fn(*mut c_void, c_int, *const c_char, f64),
        media_info: extern "C" fn(*mut c_void, *mut f64),
        mirror_started: extern "C" fn(*mut c_void),
    ) -> *mut c_void;
    fn anydeck_uxplay_stop(handle: *mut c_void);
    fn anydeck_uxplay_port(handle: *mut c_void) -> u16;
    fn anydeck_uxplay_disconnect_slot(handle: *mut c_void, slot_context: *mut c_void);
}

static ATTACHED_SLOTS: OnceLock<Mutex<HashMap<usize, u64>>> = OnceLock::new();

fn attached_slots() -> &'static Mutex<HashMap<usize, u64>> {
    ATTACHED_SLOTS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// 回调上下文，避免引用环
struct Context {
    status: Arc<AtomicU8>,
    error: Arc<Mutex<String>>,
    client_info: Arc<Mutex<(String, String, String)>>,
    frame: Arc<Frame>,
    decoder: Mutex<Decoder>,
    audio_decoder: Mutex<Option<AirPlayAudioDecoder>>,
    media: Arc<Mutex<super::media::MediaState>>,
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
            client_info: server.client_info.clone(),
            frame: server.frame.clone(),
            decoder: Mutex::new(Decoder::new(server.frame.clone())),
            audio_decoder: Mutex::new(None),
            media: server.media.clone(),
        });

        let name_c = CString::new(name).map_err(|e| e.to_string())?;
        let base_mac = AirPlayServer::get_local_mac();
        // 多台设备并发投屏时，备用广播实例通过调整 MAC 末字节避免 Bonjour _raop._tcp 冲突
        let mac = Self::derive_instance_mac(&base_mac, name);
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
                Self::on_audio_data,
                Self::on_stream_reset,
                Self::on_log_message,
                Self::on_client_request,
                Self::on_client_detach,
                Self::on_media_command,
                Self::on_media_info,
                Self::on_mirror_started,
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

    // 只由 type 110 镜像启动回调调用，音频/HTTP 视频不能触发手机窗口。
    extern "C" fn on_mirror_started(ctx: *mut c_void) {
        if ctx.is_null() { return; }
        let context = unsafe { &*(ctx as *const Context) };
        let _ = context.status.compare_exchange(
            AirPlayStatus::Idle as u8, AirPlayStatus::MirrorStarting as u8,
            Ordering::AcqRel, Ordering::Acquire);
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
            if context.frame.has_surface() && context.status.fetch_update(
                Ordering::AcqRel, Ordering::Acquire, |status|
                    (status == AirPlayStatus::Idle as u8 || status == AirPlayStatus::MirrorStarting as u8)
                        .then_some(AirPlayStatus::Mirroring as u8)).is_ok() {
                eprintln!("[AirPlay UxPlay] First decoded IOSurface ready");
            }
        });
    }

    // C 回调只更新短小的状态快照；UI/网络播放器工作不在协议线程执行。
    extern "C" fn on_media_command(ctx: *mut c_void, command: c_int, url: *const c_char, value: f64) {
        if ctx.is_null() { return; }
        let _ = std::panic::catch_unwind(|| {
            let context = unsafe { &*(ctx as *const Context) };
            if context.status.load(Ordering::Acquire) == AirPlayStatus::Stopped as u8 { return; }
            let url = if url.is_null() { None } else { unsafe { CStr::from_ptr(url).to_str().ok() } };
            if let Ok(mut media) = context.media.lock() {
                if let Err(error) = media.command(command, url, value) {
                    context.record_error(error.to_string());
                }
            };
        });
    }

    extern "C" fn on_media_info(ctx: *mut c_void, values: *mut f64) {
        if ctx.is_null() || values.is_null() { return; }
        let _ = std::panic::catch_unwind(|| {
            let context = unsafe { &*(ctx as *const Context) };
            if let Ok(media) = context.media.lock() {
                let info = media.playback_info();
                unsafe { std::ptr::copy_nonoverlapping(info.as_ptr(), values, info.len()); }
            };
        });
    }

    extern "C" fn on_audio_data(ctx: *mut c_void, data: *const u8, len: c_int, ct: u8, spf: u16) {
        if ctx.is_null() || data.is_null() || len <= 0 || len > 4096 { return; }
        let _ = std::panic::catch_unwind(|| {
            let context = unsafe { &*(ctx as *const Context) };
            if context.status.load(Ordering::Acquire) == AirPlayStatus::Stopped as u8 { return; }
            let Ok(mut audio_guard) = context.audio_decoder.lock() else { return; };
            let needs_reinit = match &*audio_guard {
                Some(dec) => {
                    if dec.is_stalled() { eprintln!("[AirPlay Audio] playback stalled; rebuilding AudioQueue"); }
                    dec.should_reinit(ct, spf)
                }
                None => true,
            };
            if needs_reinit {
                *audio_guard = AirPlayAudioDecoder::new(ct, spf).ok();
            }
            if let Some(dec) = audio_guard.as_mut() {
                let slice = unsafe { std::slice::from_raw_parts(data, len as usize) };
                dec.enqueue(slice);
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
                let _ = context.status.fetch_update(Ordering::AcqRel, Ordering::Acquire, |status|
                    (status != AirPlayStatus::Stopped as u8).then_some(AirPlayStatus::Idle as u8));
            }
            if let Ok(mut audio_guard) = context.audio_decoder.lock() {
                *audio_guard = None;
            }
        });
    }

    extern "C" fn on_log_message(ctx: *mut c_void, level: c_int, msg: *const c_char) {
        if ctx.is_null() || msg.is_null() { return; }
        let _ = std::panic::catch_unwind(|| {
            let context = unsafe { &*(ctx as *const Context) };
            let raw = unsafe { CStr::from_ptr(msg).to_string_lossy() };
            // 上游 HLS 错误可能包含签名媒体 URL，不写入日志或导出诊断。
            let text = if raw.contains("://") { "media URL diagnostic redacted" } else { raw.as_ref() };
            if level <= 4 {
                context.record_error(format!("UxPlay: {text}"));
            } else if level <= 6 {
                eprintln!("[UxPlay] {text}");
            }
        });
    }

    extern "C" fn on_client_request(
        ctx: *mut c_void,
        device_id: *const c_char,
        model: *const c_char,
        name: *const c_char,
    ) -> *mut c_void {
        if ctx.is_null() { return std::ptr::null_mut(); }
        std::panic::catch_unwind(|| {
            let dev_str = if device_id.is_null() { String::new() } else {
                unsafe { CStr::from_ptr(device_id).to_string_lossy().trim().to_string() }
            };
            let model_str = if model.is_null() { String::new() } else {
                unsafe { CStr::from_ptr(model).to_string_lossy().trim().to_string() }
            };
            let name_str = if name.is_null() { String::new() } else {
                unsafe { CStr::from_ptr(name).to_string_lossy().trim().to_string() }
            };

            let servers = crate::c_api_airplay::list_registered_servers();
            if let Ok(mut slots) = attached_slots().lock() {
                let chosen = servers
                    .iter()
                    .find(|s| {
                        !dev_str.is_empty()
                            && s.client_info.lock().map(|i| i.0 == dev_str).unwrap_or(false)
                    })
                    .or_else(|| {
                        servers.iter().find(|s| {
                            s.status.load(Ordering::Acquire) != AirPlayStatus::Stopped as u8
                                && !slots.values().any(|&occupied_id| occupied_id == s.id)
                        })
                    })
                    .cloned();

                if let Some(server) = chosen {
                    if let Ok(mut info) = server.client_info.lock() {
                        *info = (dev_str, model_str, name_str);
                    }
                    let slot_ctx = Box::new(Context {
                        status: server.status.clone(),
                        error: server.last_error.clone(),
                        client_info: server.client_info.clone(),
                        frame: server.frame.clone(),
                        decoder: Mutex::new(Decoder::new(server.frame.clone())),
                        audio_decoder: Mutex::new(None),
                        media: server.media.clone(),
                    });
                    let ptr = Box::into_raw(slot_ctx);
                    slots.insert(ptr as usize, server.id);
                    return ptr as *mut c_void;
                }
            }

            let context = unsafe { &*(ctx as *const Context) };
            if let Ok(mut info) = context.client_info.lock() {
                *info = (dev_str, model_str, name_str);
            }
            ctx
        })
        .unwrap_or(std::ptr::null_mut())
    }

    extern "C" fn on_client_detach(primary_ctx: *mut c_void, slot_ctx: *mut c_void) {
        if slot_ctx.is_null() { return; }
        let _ = std::panic::catch_unwind(|| {
            if slot_ctx == primary_ctx {
                let context = unsafe { &*(primary_ctx as *const Context) };
                if let Ok(mut info) = context.client_info.lock() {
                    *info = (String::new(), String::new(), String::new());
                }
                return;
            }
            let (removed_id, still_attached) = if let Ok(mut slots) = attached_slots().lock() {
                let id = slots.remove(&(slot_ctx as usize));
                let active = id.map(|sid| slots.values().any(|&v| v == sid)).unwrap_or(false);
                (id, active)
            } else {
                (None, false)
            };
            let ctx = unsafe { Box::from_raw(slot_ctx as *mut Context) };
            if removed_id.is_some() && !still_attached {
                ctx.frame.clear();
                let _ = ctx.status.compare_exchange(
                    AirPlayStatus::Mirroring as u8,
                    AirPlayStatus::Idle as u8,
                    Ordering::AcqRel,
                    Ordering::Acquire,
                );
                if let Ok(mut info) = ctx.client_info.lock() {
                    *info = (String::new(), String::new(), String::new());
                }
            }
        });
    }

    pub fn disconnect_slot(&self, slot_ctx: *mut c_void) {
        if !self.native.is_null() && !slot_ctx.is_null() {
            unsafe {
                anydeck_uxplay_disconnect_slot(self.native, slot_ctx);
            }
        }
    }

    pub fn find_slot_ptrs_for_server(server_id: u64) -> Vec<usize> {
        attached_slots()
            .lock()
            .map(|slots| {
                slots
                    .iter()
                    .filter_map(|(&ptr, &sid)| (sid == server_id).then_some(ptr))
                    .collect()
            })
            .unwrap_or_default()
    }

    fn derive_instance_mac(base_mac: &str, name: &str) -> String {
        let Some((_, suffix)) = name.rsplit_once('#') else {
            return base_mac.to_string();
        };
        let Ok(index) = suffix.trim().parse::<u8>() else {
            return base_mac.to_string();
        };
        if index <= 1 || base_mac.len() < 17 {
            return base_mac.to_string();
        }
        let Ok(last_byte) = u8::from_str_radix(&base_mac[15..17], 16) else {
            return base_mac.to_string();
        };
        format!("{}{:02X}", &base_mac[..15], last_byte.wrapping_add(index - 1))
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
