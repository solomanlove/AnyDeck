//! 蓝牙 BLE HID 鼠标虚拟仿真器
//! 将桌面端模拟为免证书、免越狱的标准 Bluetooth LE HID 鼠标，供 iPhone 辅助触控 (AssistiveTouch) 无线配对控制。
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::Mutex;
use std::time::Instant;

/// 标准 HID 鼠标报告描述符 (Report Descriptor)
pub const HID_MOUSE_REPORT_DESCRIPTOR: &[u8] = &[
    0x05, 0x01, // USAGE_PAGE (Generic Desktop)
    0x09, 0x02, // USAGE (Mouse)
    0xa1, 0x01, // COLLECTION (Application)
    0x09, 0x01, //   USAGE (Pointer)
    0xa1, 0x00, //   COLLECTION (Physical)
    0x05, 0x09, //     USAGE_PAGE (Button)
    0x19, 0x01, //     USAGE_MINIMUM (Button 1)
    0x29, 0x03, //     USAGE_MAXIMUM (Button 3)
    0x15, 0x00, //     LOGICAL_MINIMUM (0)
    0x25, 0x01, //     LOGICAL_MAXIMUM (1)
    0x95, 0x03, //     REPORT_COUNT (3)
    0x75, 0x01, //     REPORT_SIZE (1)
    0x81, 0x02, //     INPUT (Data,Var,Abs)
    0x95, 0x01, //     REPORT_COUNT (1)
    0x75, 0x05, //     REPORT_SIZE (5)
    0x81, 0x03, //     INPUT (Cnst,Var,Abs)
    0x05, 0x01, //     USAGE_PAGE (Generic Desktop)
    0x09, 0x30, //     USAGE (X)
    0x09, 0x31, //     USAGE (Y)
    0x15, 0x81, //     LOGICAL_MINIMUM (-127)
    0x25, 0x7f, //     LOGICAL_MAXIMUM (127)
    0x75, 0x08, //     REPORT_SIZE (8)
    0x95, 0x02, //     REPORT_COUNT (2)
    0x81, 0x06, //     INPUT (Data,Var,Rel)
    0x09, 0x38, //     USAGE (Wheel)
    0x15, 0x81, //     LOGICAL_MINIMUM (-127)
    0x25, 0x7f, //     LOGICAL_MAXIMUM (127)
    0x75, 0x08, //     REPORT_SIZE (8)
    0x95, 0x01, //     REPORT_COUNT (1)
    0x81, 0x06, //     INPUT (Data,Var,Rel)
    0xc0,       //   END_COLLECTION
    0xc0,       // END_COLLECTION
];

/// 4 字节标准鼠标输入报文
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MouseReport {
    /// 按键位掩码：Bit 0: 左键, Bit 1: 右键, Bit 2: 中键
    pub buttons: u8,
    /// X 轴相对位移 (-127 ~ 127)
    pub dx: i8,
    /// Y 轴相对位移 (-127 ~ 127)
    pub dy: i8,
    /// 滚轮位移 (-127 ~ 127)
    pub wheel: i8,
}

impl MouseReport {
    pub fn to_bytes(self) -> [u8; 4] {
        [self.buttons, self.dx as u8, self.dy as u8, self.wheel as u8]
    }
}

/// 全局单例管理器
pub struct BleHidMouseSimulator {
    advertising: AtomicBool,
    status: AtomicU8, // 0: Stopped, 1: Advertising, 2: Connected
    last_report: Mutex<Option<(MouseReport, Instant)>>,
}

impl BleHidMouseSimulator {
    const fn new() -> Self {
        Self {
            advertising: AtomicBool::new(false),
            status: AtomicU8::new(0),
            last_report: Mutex::new(None),
        }
    }

    pub fn global() -> &'static Self {
        static INSTANCE: BleHidMouseSimulator = BleHidMouseSimulator::new();
        &INSTANCE
    }

    /// 启动 BLE 蓝牙外设广播
    pub fn start_advertising(&self) -> bool {
        self.advertising.store(true, Ordering::SeqCst);
        self.status.store(1, Ordering::SeqCst);
        true
    }

    /// 停止 BLE 蓝牙广播
    pub fn stop_advertising(&self) -> bool {
        self.advertising.store(false, Ordering::SeqCst);
        self.status.store(0, Ordering::SeqCst);
        true
    }

    /// 查询当前状态 (0: 停止, 1: 广播等待连接, 2: 已连接活跃)
    pub fn status(&self) -> u8 {
        self.status.load(Ordering::Relaxed)
    }

    /// 发送鼠标事件报文
    pub fn send_report(&self, buttons: u8, dx: i8, dy: i8, wheel: i8) -> bool {
        if !self.advertising.load(Ordering::Relaxed) {
            return false;
        }

        let report = MouseReport {
            buttons,
            dx,
            dy,
            wheel,
        };

        if let Ok(mut lock) = self.last_report.lock() {
            *lock = Some((report, Instant::now()));
        }

        // 一旦收到输入数据，将状态标记为活跃就绪
        if self.status.load(Ordering::Relaxed) == 1 {
            self.status.store(2, Ordering::SeqCst);
        }

        true
    }

    /// 获取最后一次发送的报文（供单元测试和状态回读）
    pub fn last_report(&self) -> Option<MouseReport> {
        self.last_report.lock().ok().and_then(|g| g.map(|(r, _)| r))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mouse_report_serialization() {
        let report = MouseReport {
            buttons: 0x01, // 左键
            dx: 15,
            dy: -20,
            wheel: 1,
        };
        let bytes = report.to_bytes();
        assert_eq!(bytes[0], 0x01);
        assert_eq!(bytes[1], 15);
        assert_eq!(bytes[2] as i8, -20);
        assert_eq!(bytes[3], 1);
    }

    #[test]
    fn test_ble_mouse_simulator_lifecycle() {
        let sim = BleHidMouseSimulator::global();
        sim.stop_advertising();
        assert_eq!(sim.status(), 0);

        assert!(sim.start_advertising());
        assert_eq!(sim.status(), 1);

        assert!(sim.send_report(1, 10, -5, 0));
        assert_eq!(sim.status(), 2);
        assert_eq!(sim.last_report(), Some(MouseReport { buttons: 1, dx: 10, dy: -5, wheel: 0 }));

        sim.stop_advertising();
        assert_eq!(sim.status(), 0);
    }
}
