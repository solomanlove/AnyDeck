//! iOS 设备驱动实现 (为阶段四 iOS 投屏反控与自动化生态预留)
use async_trait::async_trait;
use super::driver::{DeviceDriver, DevicePlatform};

/// iOS 平台专用设备驱动
pub struct IosDriver {
    udid: String,
}

impl IosDriver {
    /// 创建指定 UDID 的 iOS 设备驱动实例
    pub fn new(udid: impl Into<String>) -> Self {
        Self {
            udid: udid.into(),
        }
    }
}

#[async_trait]
impl DeviceDriver for IosDriver {
    fn id(&self) -> &str {
        &self.udid
    }

    fn platform(&self) -> DevicePlatform {
        DevicePlatform::Ios
    }

    async fn execute_shell(&self, _cmd: &str) -> Result<String, String> {
        Err("IosDriver is scheduled for Phase 4 (WDA/go-ios integration)".into())
    }

    async fn take_screenshot(&self) -> Result<Vec<u8>, String> {
        Err("IosDriver::take_screenshot is scheduled for Phase 4".into())
    }

    async fn push_file(&self, _local: &str, _remote: &str) -> Result<(), String> {
        Err("IosDriver::push_file is scheduled for Phase 4".into())
    }
}
