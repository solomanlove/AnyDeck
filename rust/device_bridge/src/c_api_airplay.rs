//! AirPlay Server 屏幕镜像 C-ABI 导出层
//! 供 Dart FFI 及 macOS Flutter 外部纹理直接获取 CVPixelBuffer

use std::collections::HashMap;
use std::ffi::{c_char, c_void, CStr};
use std::ptr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use crate::airplay::{AirPlayServer, AirPlayStatus};

static AIRPLAY_SERVERS: OnceLock<Mutex<HashMap<u64, Arc<AirPlayServer>>>> = OnceLock::new();
static NEXT_AIRPLAY_ID: AtomicU64 = AtomicU64::new(1000);

fn servers() -> &'static Mutex<HashMap<u64, Arc<AirPlayServer>>> {
    AIRPLAY_SERVERS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn get_server(id: u64) -> Option<Arc<AirPlayServer>> {
    servers().lock().ok()?.get(&id).cloned()
}

/// 启动 AirPlay 屏幕镜像服务
/// - `name`: 设备名 (如 "AnyDeck-Mac")
/// - `rtsp_port`: RTSP 控制端口 (通常 7000，传 0 则默认 7000)
/// - `video_port`: 视频流端口 (通常 7100，传 0 则默认 7100)
/// 返回服务会话 ID (失败返回 0)
///
/// # Safety
/// `name` 必须是指向有效 NUL 结尾 UTF-8 字符串的指针。
#[no_mangle]
pub unsafe extern "C" fn anydeck_airplay_start(
    name: *const c_char,
    rtsp_port: u16,
    video_port: u16,
) -> u64 {
    if name.is_null() {
        return 0;
    }

    let Ok(name_str) = CStr::from_ptr(name).to_str() else {
        return 0;
    };

    let p_rtsp = if rtsp_port == 0 { 7000 } else { rtsp_port };
    let p_video = if video_port == 0 { 7100 } else { video_port };

    let id = NEXT_AIRPLAY_ID.fetch_add(1, Ordering::Relaxed);

    match AirPlayServer::start(id, name_str, p_rtsp, p_video) {
        Ok(server) => {
            if let Ok(mut map) = servers().lock() {
                map.insert(id, server);
                id
            } else {
                0
            }
        }
        Err(e) => {
            eprintln!("anydeck_airplay_start error: {e}");
            0
        }
    }
}

/// 停止并销毁指定的 AirPlay 投屏服务
#[no_mangle]
pub extern "C" fn anydeck_airplay_stop(id: u64) {
    // join native 线程前释放全局表锁，避免 Texture/状态轮询被停止操作卡住。
    let server = servers().lock().ok().and_then(|mut map| map.remove(&id));
    if let Some(server) = server {
        server.stop();
    }
}

/// 获取当前最新的 CVPixelBufferRef 视频帧指针 (引用计数 +1)
/// 调用方通过 CFRelease 释放。
#[no_mangle]
pub extern "C" fn anydeck_airplay_get_frame(id: u64) -> *mut c_void {
    get_server(id).map(|s| s.frame.copy()).unwrap_or(ptr::null_mut())
}

/// 检查当前帧是否具备 IOSurface 硬件加速表面
#[no_mangle]
pub extern "C" fn anydeck_airplay_has_surface(id: u64) -> bool {
    get_server(id).map(|s| s.frame.has_surface()).unwrap_or(false)
}

/// 返回 AirPlay 会话累计产出的可渲染帧数。
pub fn anydeck_airplay_decoded_frames(id: u64) -> u64 {
    get_server(id).map(|s| s.frame.produced()).unwrap_or(0)
}

/// 读取当前投屏分辨率宽度和高度
#[no_mangle]
pub unsafe extern "C" fn anydeck_airplay_get_dimensions(
    id: u64,
    out_width: *mut u32,
    out_height: *mut u32,
) -> bool {
    if out_width.is_null() || out_height.is_null() {
        return false;
    }

    let Some(server) = get_server(id) else {
        return false;
    };

    let (w, h) = server.frame.dimensions();
    *out_width = w;
    *out_height = h;
    w > 0 && h > 0
}

/// 获取 AirPlay 当前状态
/// 0: Idle (待机等待连接), 1: Mirroring (投屏中), 2: Stopped (已停止)
#[no_mangle]
pub extern "C" fn anydeck_airplay_get_status(id: u64) -> u8 {
    get_server(id)
        .map(|s| s.status.load(Ordering::Acquire))
        .unwrap_or(AirPlayStatus::Stopped as u8)
}

/// 复制最近一次 AirPlay 错误的 UTF-8 字节，无 NUL 结尾，返回写入长度。
///
/// # Safety
/// `out` 须指向至少 `capacity` 字节的可写区域。
#[no_mangle]
pub unsafe extern "C" fn anydeck_airplay_copy_last_error(id: u64, out: *mut u8, capacity: usize) -> usize {
    if out.is_null() || capacity == 0 { return 0; }
    let Some(server) = get_server(id) else { return 0; };
    let Ok(error) = server.last_error.lock() else { return 0; };
    let length = error.len().min(capacity);
    ptr::copy_nonoverlapping(error.as_ptr(), out, length);
    length
}
