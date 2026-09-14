//! 鸿蒙 (HarmonyOS) 设备驱动实现 (为阶段三 HDC 驱动集成预留)
use async_trait::async_trait;
use super::driver::{DeviceDriver, DevicePlatform};

/// 鸿蒙平台专用设备驱动
pub struct HarmonyDriver {
    target: String,
}

impl HarmonyDriver {
    /// 创建指定目标标识的鸿蒙设备驱动实例
    pub fn new(target: impl Into<String>) -> Self {
        Self {
            target: target.into(),
        }
    }
}

#[async_trait]
impl DeviceDriver for HarmonyDriver {
    fn id(&self) -> &str {
        &self.target
    }

    fn platform(&self) -> DevicePlatform {
        DevicePlatform::Harmony
    }

    async fn execute_shell(&self, _cmd: &str) -> Result<String, String> {
        Err("HarmonyDriver is scheduled for Phase 3 (HDC integration)".into())
    }

    async fn take_screenshot(&self) -> Result<Vec<u8>, String> {
        Err("HarmonyDriver::take_screenshot is scheduled for Phase 3".into())
    }

    async fn push_file(&self, _local: &str, _remote: &str) -> Result<(), String> {
        Err("HarmonyDriver::push_file is scheduled for Phase 3".into())
    }
}
