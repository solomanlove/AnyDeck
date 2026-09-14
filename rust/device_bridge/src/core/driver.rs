//! 统一设备抽象层 (Device Abstraction Layer, DAL) 核心 Trait 定义
use async_trait::async_trait;
use serde::{Deserialize, Serialize};

/// 目标设备硬件平台类型
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum DevicePlatform {
    Android = 0,
    Harmony = 1,
    Ios = 2,
}

impl DevicePlatform {
    /// 从原始整数转换为强类型枚举
    pub fn from_u8(val: u8) -> Option<Self> {
        match val {
            0 => Some(Self::Android),
            1 => Some(Self::Harmony),
            2 => Some(Self::Ios),
            _ => None,
        }
    }
}

/// 统一跨平台设备驱动抽象 Trait
/// 为上层业务提供一致的设备控制契约，屏蔽 Android/鸿蒙/iOS 底层通信差异
#[async_trait]
pub trait DeviceDriver: Send + Sync {
    /// 唯一设备标识符 (Android Serial / 鸿蒙 Target ID / iOS UDID)
    fn id(&self) -> &str;

    /// 设备所属硬件平台
    fn platform(&self) -> DevicePlatform;

    /// 异步执行底层控制台指令 (ADB shell / HDC shell / iOS test CLI)
    async fn execute_shell(&self, cmd: &str) -> Result<String, String>;

    /// 抓取全屏截图 (返回统一的 PNG 编码二进制字节)
    async fn take_screenshot(&self) -> Result<Vec<u8>, String>;

    /// 推送本地文件至设备指定目录
    async fn push_file(&self, local: &str, remote: &str) -> Result<(), String>;
}
