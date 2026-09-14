# 核心技术架构与原理解析 (Core Architecture & Principles)

本文档深入解析 AnyDeck 跨平台底座重构涉及的核心技术原理、协议报文格式、计算公式与关键数据结构，供后续开发与维护查阅。

---

## 一、Direct ADB Socket 协议原理 (AOSP Wire Protocol)

### 1. 通信机制
ADB Client 与运行在宿主机本地的 `adb server`（默认监听 `127.0.0.1:5037`）采用极简的二进制报文协议：
- **请求报文结构**：`[4 字节十六进制 ASCII 长度] + [Payload 字符串]`
- **响应头结构**：`OKAY`（4 字节，成功）或 `FAIL`（4 字节，失败）+ `[4 字节错误信息长度] + [错误内容]`

### 2. 核心控制指令报文

```text
1. 切换目标设备会话:
   "0012host:transport:192.168.1.100:5555"
    └── 0x0012 = 18 字节长度

2. 请求执行 Shell 命令:
   "001fshell:cat /proc/stat; dumpsys ..."
    └── 0x001f = 31 字节长度
```

一旦 `shell:` 获得 `OKAY` 回应，该 TCP 连接直接转为 Raw 字节流管道，直到命令执行完毕由远端关闭（EOF）。

---

## 二、零拷贝（Zero-Copy）性能采样与算法

### 1. 内存模型对比
- **旧实现 (Dart VM)**：
  $$\text{Raw Bytes} \xrightarrow{\text{UTF8 Decode}} \text{String} \xrightarrow{\text{Split}} [\text{Sections}] \xrightarrow{\text{RegExp}} \text{Objects} \xrightarrow{\text{GC Drop}}$$
  每秒在托管堆上创建数百个瞬时垃圾对象，触发周期性垃圾回收。
- **新实现 (Rust Native)**：
  $$\text{Raw Bytes (Buffer)} \xrightarrow{\text{In-place Slice } \&[u8]} \text{C-ABI Struct Pointer (Fixed Memory)}$$
  全程零堆内存分配（Zero Allocation），耗时小于 $50\,\mu\text{s}$。

### 2. 数学计算公式

#### CPU 使用率增量算法：
从 `/proc/stat` 的第一行 `cpu` 读取时间片指标：
$$Total = user + nice + system + idle + iowait + irq + softirq + steal$$
$$Idle = idle + iowait$$

在两个连续采样周期 $t_1$ 和 $t_2$ 间：
$$\Delta Total = Total_{t2} - Total_{t1}$$
$$\Delta Idle = Idle_{t2} - Idle_{t1}$$
$$\text{Usage}\% = \begin{cases} 
\left(1 - \frac{\Delta Idle}{\Delta Total}\right) \times 100\%, & \text{if } \Delta Total > 0 \\
0.0\%, & \text{otherwise}
\end{cases}$$

#### 实时渲染 FPS 算法：
从 `dumpsys gfxinfo <package>` 提取累计渲染总帧数 $F$：
$$\Delta F = F_{t2} - F_{t1}$$
$$\Delta t = \frac{\text{Timestamp}_{t2} - \text{Timestamp}_{t1}}{1000.0} \quad (\text{单位: 秒})$$
$$\text{FPS} = \text{clamp}\left(\frac{\Delta F}{\Delta t}, 0.0, 120.0\right)$$

---

## 三、统一设备抽象层 (DAL) Trait 设计

Rust 侧定义统一抽象，使得上层业务完全解耦设备类型：

```rust
// rust/device_bridge/src/core/driver.rs
use async_trait::async_trait;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DevicePlatform {
    Android,
    Harmony,
    Ios,
}

#[async_trait]
pub trait DeviceDriver: Send + Sync {
    /// 唯一设备标识 (Android Serial / 鸿蒙 Target / iOS UDID)
    fn id(&self) -> &str;
    
    /// 设备所属平台
    fn platform(&self) -> DevicePlatform;

    /// 异步执行控制台指令
    async fn execute_shell(&self, cmd: &str) -> Result<String, String>;

    /// 抓取全屏截图 (返回统一的 PNG 编码字节)
    async fn take_screenshot(&self) -> Result<Vec<u8>, String>;

    /// 推送本地文件至设备指定目录
    async fn push_file(&self, local: &str, remote: &str) -> Result<(), String>;
}
```

---

## 四、Android 14+ 融合模式 (App Fusion Mode) 原理

### 1. 为什么必须 Android 14+？
- **DisplayManager 权限演进**：在 Android 13 之前，Shell 权限创建的 VirtualDisplay 缺乏 `VIRTUAL_DISPLAY_FLAG_OWN_FOCUS`。任何输入事件容易被默认的主屏幕（Display 0）拦截或打乱，锁屏后虚拟屏自动销毁。
- **Android 14 (API 34) 质变**：Google 重构了桌面模式底层，允许赋予虚拟屏独立的输入焦点队列，并支持 `am start --display <id>` 将 Task 隔离在指定 Display 运行。

### 2. 关键控制命令与参数

```bash
# 1. 启动 scrcpy-server 时注入虚拟屏参数 (宽x高/DPI)
new_display=450x800/320 vd_system_decorations=false

# 2. 将目标应用定向投放至该虚拟屏
am start --display <displayId> -n <com.pkg/.Activity> -f 0x10000000

# 3. 电脑窗口缩放时动态重置虚拟屏参数 (触发 Android 重新布局)
# 控制报文发送 RESIZE_DISPLAY: width, height, dpi
```

### 3. 带 display_id 的触控注入报文格式

```rust
#[repr(C, packed)]
pub struct ScrcpyTouchControlMsg {
    pub msg_type: u8,      // 2 = SC_CONTROL_MSG_TYPE_INJECT_TOUCH_EVENT
    pub action: u8,        // 0 = DOWN, 1 = UP, 2 = MOVE
    pub pointer_id: u64,
    pub x: u32,
    pub y: u32,
    pub width: u16,
    pub height: u16,
    pub pressure: u16,
    pub action_button: u32,
    pub buttons: u32,
    pub display_id: u32,   // 关键：指定目标虚拟屏幕 ID
}
```

---

## 五、iOS 反向控制与投屏原理

### 1. 蓝牙 BLE HID 虚拟外设控制原理 (无证书、无越狱方案)
- **底层基础**：iOS 13+ 内置了完整的“辅助触控（AssistiveTouch）”光标体系，能够原生响应蓝牙 HID 鼠标设备。
- **工作链路**：
  1. AnyDeck 宿主机（Mac/PC）开启蓝牙广播，声明为标准 **HID Composite Device (Mouse & Keyboard)**。
  2. iPhone 在蓝牙中搜索并与电脑完成配对，进入 **设置 $\rightarrow$ 辅助功能 $\rightarrow$ 触控 $\rightarrow$ 辅助触控** 开启。
  3. Flutter 投屏窗口捕获鼠标移动和点击坐标，Rust 封包为标准 HID Mouse Report：
     ```rust
     // 标准 4 字节 HID 鼠标报文
     struct HidMouseReport {
         buttons: u8,   // bit 0: Left, bit 1: Right, bit 2: Middle
         dx: i8,        // X 轴相对位移
         dy: i8,        // Y 轴相对位移
         wheel: i8,     // 滚轮位移
     }
     ```
  4. 电脑直接通过空中蓝牙电磁波将 Report 发送给 iPhone，光标即时跟随响应，延迟 $< 15\,\text{ms}$。

### 2. WebDriverAgent (WDA) 自动化接口 (批量任务方案)
- 基于 Apple 私有测试框架 `XCEventGenerator`，通过 HTTP 协议注入精准屏幕绝对坐标：
  ```http
  POST /session/:id/wda/touchAndHold
  Content-Type: application/json

  {
    "x": 200,
    "y": 450,
    "duration": 0.05
  }
  ```
