//! Android 设备驱动实现：基于 Direct ADB Socket 通信直连 AOSP adbd，彻底避免进程 Fork/Exec
use std::time::Duration;
use async_trait::async_trait;
use crate::adb_socket::AdbSocketClient;
use super::driver::{DeviceDriver, DevicePlatform};

/// Android 平台专用设备驱动
pub struct AndroidDriver {
    serial: String,
}

impl AndroidDriver {
    /// 创建指定序列号的 Android 设备驱动实例
    pub fn new(serial: impl Into<String>) -> Self {
        Self {
            serial: serial.into(),
        }
    }
}

#[async_trait]
impl DeviceDriver for AndroidDriver {
    fn id(&self) -> &str {
        &self.serial
    }

    fn platform(&self) -> DevicePlatform {
        DevicePlatform::Android
    }

    /// 异步执行 ADB Shell 指令，使用 Direct Socket 通信
    async fn execute_shell(&self, cmd: &str) -> Result<String, String> {
        let serial = self.serial.clone();
        let cmd = cmd.to_string();

        tokio::task::spawn_blocking(move || {
            let bytes = AdbSocketClient::execute_shell(&serial, &cmd, Duration::from_secs(30))?;
            Ok(String::from_utf8_lossy(&bytes).into_owned())
        })
        .await
        .map_err(|e| format!("Tokio join error: {e}"))?
    }

    /// 异步抓取设备当前屏幕截图并返回 PNG 字节流
    async fn take_screenshot(&self) -> Result<Vec<u8>, String> {
        let serial = self.serial.clone();

        tokio::task::spawn_blocking(move || {
            let bytes = AdbSocketClient::execute_shell(&serial, "screencap -p", Duration::from_secs(15))?;
            if bytes.is_empty() {
                return Err("Empty screenshot returned from device".into());
            }
            Ok(bytes)
        })
        .await
        .map_err(|e| format!("Tokio join error: {e}"))?
    }

    /// 推送本地文件到远程设备 (后续阶段集成 Direct ADB Sync 协议)
    async fn push_file(&self, _local: &str, _remote: &str) -> Result<(), String> {
        Err("AndroidDriver::push_file not yet implemented via direct socket".into())
    }
}
