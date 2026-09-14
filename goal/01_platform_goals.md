# 三端目标愿景与能力矩阵 (Platform Goals & Feature Matrix)

本文档明确定义 AnyDeck 在 **Android**、**鸿蒙 (HarmonyOS NEXT)** 与 **iOS** 三大主流移动操作系统上的能力目标与业务支持边界。

---

## 一、三端整体支持矩阵

| 功能模块 | Android 目标能力 | 鸿蒙 (HarmonyOS) 目标能力 | iOS 目标能力 |
| :--- | :--- | :--- | :--- |
| **底层通信协议** | Rust Direct Socket (`127.0.0.1:5037`) | Rust 异步进程管道池 (`hdc`) | 原生 `usbmuxd` Socket + `go-ios` 隧道 |
| **实时性能监控** | 零拷贝 `/proc/stat`、Meminfo、FPS 计算 | `hdc shell param get`、基础资源监控 | 基础状态 (Battery, Thermal, IO) |
| **屏幕投屏 (Mirror)** | Scrcpy 原生硬解 (VideoToolbox / DXVA) | Scrcpy 协议或 HDC 原生端口映射 | USB (MJPEG 字节流硬解) / 无线 (AirPlay) |
| **应用独立融合模式** | **支持 (Android 14+ 独占)**，独立子窗口 | 视系统后续 Multi-Window 开放度而定 | 暂不支持（苹果强沙盒限制） |
| **反向触控与输入** | Scrcpy Control (Touch, Key, Text) | HDC uinput 键鼠映射 | **双轨制**：BLE HID 蓝牙鼠标反控 + WDA |
| **日志与终端** | Logcat 环形缓冲区 (20k 条) + SIMD 过滤 | Hilog 异步流式拉取与过滤 | Syslog / OS Trace 流式拉取 |
| **文件系统管理** | 原生 ADB Sync 协议 (流式 Push/Pull) | HDC file send/recv 异步分块传输 | AFC (Apple File Conduit) 协议 |

---

## 二、Android 专项落地目标

### 1. 性能 Tab 极致优化 (Zero-Allocation & Zero-Fork)
- **彻底消除宿主机子进程创建**：废除 Dart `Process.start('adb')` 轮询，改由 Rust 原生通过 TCP Socket 连接本地 ADB Server。
- **内存占用降低 80%+**：所有 Shell 输出在 Rust 内存中以切片（`&[u8]`）原地解析，消除 Dart VM 每秒数百个小对象创建带来的 GC 卡顿。
- **结构体 FFI 传输**：Rust 维护 90 秒环形缓存，每秒向 Flutter 传递单个定长 C-ABI 结构体指针。

### 2. Android 14+ 应用融合模式 (App Fusion Mode)
- **独立虚拟屏运行**：通过 `scrcpy-server` 参数 `new_display` 在 Android 14 设备上创建独立的 `VirtualDisplay`。
- **任务定向投放**：利用 `am start --display <displayId> -n <App>` 将目标应用隔离投放到虚拟屏中。
- **桌面级多任务体验**：手机物理屏幕自由使用，电脑桌面显示独立的无边框 App 窗口；支持窗口拖拽动态 Resize 自适应 DPI；鼠标滚轮与点击精准绑定 `displayId` 注入。

### 3. Logcat 海量日志流引擎
- **无上限平滑吞吐**：Rust 端开辟 20,000 行定长紧凑内存环形队列，支持万级日志秒级刷屏。
- **高性能即时过滤**：在 Rust 侧完成 Tag、PID、Level 与关键词的正则过滤，Flutter 端采用虚拟列表仅渲染当前可视视口。

---

## 三、鸿蒙 (HarmonyOS NEXT) 专项落地目标

### 1. HDC 进程管道池与资源池化
- **避免重复启动开销**：由于鸿蒙 HDC 协议变动频繁且缺乏稳定第三方 Rust Crate，底层采用官方 `hdc` 二进制。
- **Rust 异步管道托管**：通过 `tokio::process` 与管道复用，规避 Dart 的主线程阻塞。

### 2. 统一设备接入与管理
- 将鸿蒙设备接入统一的 `DeviceDriver` Trait。
- 支持获取设备型号、SDK 版本、电量、已安装应用列表。
- 支持文件的批量推送与拉取。

### 3. 投屏与控制流对接
- 利用 `hdc fport` 进行端口映射，将鸿蒙设备的视频流无缝直连 Rust 的 `device_bridge` 渲染引擎。

---

## 四、iOS 专项落地目标

### 1. 原生高速设备发现与识别
- 直接通过 Unix Domain Socket 监听 macOS 本地 `/var/run/usbmuxd`，微秒级识别 iOS 设备插拔并读取 UDID。
- 复杂调试指令托管 `go-ios`，平滑跨越 iOS 17+ CoreDevice QUIC/RemoteXPC 隧道壁垒。

### 2. 双模式屏幕投屏
- **有线极速投屏**：读取 `go-ios` 暴露的 HTTP MJPEG 流，移交 Rust 原生提取 SOI/EOI 标志并交由 VideoToolbox 硬解码，输出 Metal 纹理给 Flutter 渲染。
- **无线 60 FPS AirPlay 投屏**：集成轻量级 AirPlay 接收协议，手机控制中心一键无线镜像，画质达 1080P@60FPS 并同步无线音频。

### 3. 电脑反向控制手机（双轨落地）
- **桌面级日常鼠标操作（零证书、零越狱）**：
  - Rust 模拟为标准的 **BLE HID 蓝牙鼠标与键盘外设**。
  - 手机仅需打开“辅助触控（AssistiveTouch）”即可通过电脑鼠标进行精准点击、拖拽滑动与文字输入。
- **批量与自动化测试脚本**：
  - 集成 WebDriverAgent (WDA) RESTful 客户端，支持按坐标、控件 ID 执行自动化测试用例。

---

## 五、跨平台批量与自动化目标

1. **批量并发限流控制**：
   - 引入 Tokio 异步框架与 `Arc<Semaphore>`（默认并发数限制为 4），在批量安装 APK、批量执行命令或批量截屏时，保护主机 USB Host Controller 避免总线过载导致设备掉线。
2. **定时自动化任务调度器 (Cron Engine)**：
   - 支持开发者预设定时规则（如“每隔 30 分钟检查一次设备发热与内存”、“定时拉取性能报告”），后台静默执行并持久化到本地 SQLite 数据库。
