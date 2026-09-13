pub mod audio_queue;
pub mod decoder;
pub mod video;
pub mod video_ffi;

use std::ffi::CStr;
use std::os::raw::{c_char, c_void};
use libc::size_t;

/// 视频帧解码回调：向平台层传递硬件解码出的 CVPixelBufferRef 句柄指针与分辨率。
pub type ScrcpyPixelBufferCallback = unsafe extern "C" fn(opaque: *mut c_void, pixel_buffer: *mut c_void, width: i32, height: i32);
pub type ScrcpyAudioCallback = unsafe extern "C" fn(opaque: *mut c_void, pcm_buf: *const u8, len: i32);

pub struct RustScrcpyDecoderContext {
    inner: decoder::ScrcpyDecoder,
}

#[no_mangle]
pub unsafe extern "C" fn rust_scrcpy_start(
    host: *const c_char,
    port: i32,
    audio_enabled: bool,
    frame_cb: ScrcpyPixelBufferCallback,
    audio_cb: ScrcpyAudioCallback,
    opaque: *mut c_void,
) -> *mut RustScrcpyDecoderContext {
    if host.is_null() {
        return std::ptr::null_mut();
    }
    let host_str = match CStr::from_ptr(host).to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return std::ptr::null_mut(),
    };

    println!("[rust_scrcpy] Starting pure Rust VideoToolbox & AudioQueue decoder for {}:{} (audio: {})", host_str, port, audio_enabled);

    let mut decoder = decoder::ScrcpyDecoder::new(host_str, port, audio_enabled, frame_cb, audio_cb, opaque);
    if !decoder.start() {
        println!("[rust_scrcpy] Failed to start Rust decoder threads");
        return std::ptr::null_mut();
    }

    Box::into_raw(Box::new(RustScrcpyDecoderContext { inner: decoder }))
}

#[no_mangle]
pub unsafe extern "C" fn rust_scrcpy_stop(ctx: *mut RustScrcpyDecoderContext) {
    if !ctx.is_null() {
        let mut boxed_ctx = Box::from_raw(ctx);
        boxed_ctx.inner.stop();
        println!("[rust_scrcpy] Rust decoder stopped and resources released");
    }
}

#[no_mangle]
pub unsafe extern "C" fn rust_scrcpy_send_control(
    ctx: *mut RustScrcpyDecoderContext,
    bytes: *const u8,
    len: size_t,
) -> bool {
    if ctx.is_null() || bytes.is_null() || len == 0 {
        return false;
    }
    let data = std::slice::from_raw_parts(bytes, len);
    (*ctx).inner.send_control_message(data)
}
