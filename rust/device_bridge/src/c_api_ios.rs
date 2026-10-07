//! iOS 设备发现与 Cron 调度的 C-ABI 导出层
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
