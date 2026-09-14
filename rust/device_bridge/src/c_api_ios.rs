//! iOS 投屏反控、BLE 虚拟鼠标、WDA 与 Cron 调度的 C-ABI 导出层
use std::ffi::{c_char, CStr};
use crate::core;

/// 查询已连接的 iOS 设备列表，返回 JSON 字符串裸指针
///
/// # Safety
/// 返回指针指向的堆内存必须由调用方通过 `anydeck_free_string` 释放。
#[no_mangle]
pub unsafe extern "C" fn anydeck_ios_list_devices() -> *mut c_char {
    let result = core::BatchManager::runtime().block_on(async {
        core::IosDriver::list_targets().await
    });

    let json_bytes = match result {
        Ok(targets) => serde_json::to_string(&targets).unwrap_or_else(|_| "[]".into()),
        Err(_) => "[]".into(),
    };

    std::ffi::CString::new(json_bytes)
        .map(|cs| cs.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// 启动蓝牙 BLE HID 鼠标广播
#[no_mangle]
pub unsafe extern "C" fn anydeck_ble_mouse_start() -> bool {
    core::BleHidMouseSimulator::global().start_advertising()
}

/// 停止蓝牙 BLE HID 鼠标广播
#[no_mangle]
pub unsafe extern "C" fn anydeck_ble_mouse_stop() -> bool {
    core::BleHidMouseSimulator::global().stop_advertising()
}

/// 发送鼠标相对位移与按键 (buttons: 1:左键, 2:右键, 4:中键)
#[no_mangle]
pub unsafe extern "C" fn anydeck_ble_mouse_send(buttons: u8, dx: i8, dy: i8, wheel: i8) -> bool {
    core::BleHidMouseSimulator::global().send_report(buttons, dx, dy, wheel)
}

/// 获取当前 BLE 鼠标状态 (0: 停止, 1: 广播中等待配对, 2: 已连接活跃)
#[no_mangle]
pub unsafe extern "C" fn anydeck_ble_mouse_status() -> u8 {
    core::BleHidMouseSimulator::global().status()
}

/// 发送轻量级 WDA HTTP 请求
///
/// # Safety
/// endpoint, method, body_json 必须为有效 NUL 结尾 C 字符串指针。
/// 返回指针指向的堆内存必须由调用方通过 `anydeck_free_string` 释放。
#[no_mangle]
pub unsafe extern "C" fn anydeck_wda_request(
    port: u16,
    endpoint: *const c_char,
    method: *const c_char,
    body_json: *const c_char,
) -> *mut c_char {
    if endpoint.is_null() || method.is_null() {
        return std::ptr::null_mut();
    }

    let Ok(ep_str) = CStr::from_ptr(endpoint).to_str() else {
        return std::ptr::null_mut();
    };
    let Ok(method_str) = CStr::from_ptr(method).to_str() else {
        return std::ptr::null_mut();
    };
    let body_str = if !body_json.is_null() {
        CStr::from_ptr(body_json).to_str().ok()
    } else {
        None
    };

    let url = format!("http://127.0.0.1:{port}{ep_str}");
    let result = core::BatchManager::runtime().block_on(async {
        core::IosDriver::execute_http_request(&url, method_str, body_str, std::time::Duration::from_secs(5)).await
    });

    let (success, payload) = match result {
        Ok(res) => (true, res),
        Err(e) => (false, e),
    };

    let response = serde_json::json!({
        "success": success,
        "payload": payload,
    });

    std::ffi::CString::new(response.to_string())
        .map(|cs| cs.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// 注册或更新 Cron 定时任务
///
/// # Safety
/// id, name, expression 必须为有效 NUL 结尾 C 字符串指针。
#[no_mangle]
pub unsafe extern "C" fn anydeck_cron_add_job(
    id: *const c_char,
    name: *const c_char,
    expression: *const c_char,
) -> bool {
    if id.is_null() || name.is_null() || expression.is_null() {
        return false;
    }
    let (Ok(id_s), Ok(name_s), Ok(expr_s)) = (
        CStr::from_ptr(id).to_str(),
        CStr::from_ptr(name).to_str(),
        CStr::from_ptr(expression).to_str(),
    ) else {
        return false;
    };

    core::CronScheduler::global().add_job(id_s, name_s, expr_s).is_ok()
}

/// 移除 Cron 定时任务
///
/// # Safety
/// id 必须为有效 NUL 结尾 C 字符串指针。
#[no_mangle]
pub unsafe extern "C" fn anydeck_cron_remove_job(id: *const c_char) -> bool {
    if id.is_null() {
        return false;
    }
    let Ok(id_s) = CStr::from_ptr(id).to_str() else {
        return false;
    };
    core::CronScheduler::global().remove_job(id_s)
}

/// 获取 Cron 定时任务列表 JSON
///
/// # Safety
/// 返回指针指向的堆内存必须由调用方通过 `anydeck_free_string` 释放。
#[no_mangle]
pub unsafe extern "C" fn anydeck_cron_list_jobs() -> *mut c_char {
    let json = core::CronScheduler::global().list_jobs_json();
    std::ffi::CString::new(json)
        .map(|cs| cs.into_raw())
        .unwrap_or(std::ptr::null_mut())
}
