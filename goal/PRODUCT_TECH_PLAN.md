# AnyDeck 跨平台桌面端技术方案 (Product Technical Plan)

> **核心架构定位**：Flutter 负责 UI 渲染与视图交互；Rust 负责底层系统交互、密集型计算与跨平台设备抽象（支持 **Android / 鸿蒙 NEXT / iOS** 三端并进）。

---

## 1. 产品定位

`AnyDeck` 定位为面向移动端开发、测试、逆向与多端群控场景的 **高生产力、高性能、极低内存** 的跨平台桌面工具台。

彻底告别旧版“仅针对 Android、频繁通过 Dart 启动外部子进程（Fork/Exec）、高频轮询引发宿主机 CPU/内存抖动”的旧架构，升级为：

```text
[ Flutter Desktop UI ] (声明式 UI / 虚拟列表 / 多窗口调度)
         │  dart:ffi / NativePort (C-ABI 紧凑结构体 / 零拷贝)
[ Rust Native Core ] (Tokio 并发 / 统一 DAL / 零内存分配切片解析)
   ├── Android: Direct ADB Socket (127.0.0.1:5037) + Scrcpy 投屏 + Android 14 融合模式
   ├── 鸿蒙: HDC 异步管道池 + 8710 直连 + 原生流中转
   └── iOS: Native usbmuxd + go-ios 隧道 + BLE HID 蓝牙鼠标反控 + AirPlay 投屏
```

---

## 2. 标杆项目对比与技术路线选型

| 项目 | 技术栈 | 投屏/反控方式 | 优缺点分析 | AnyDeck 选型策略 |
| :--- | :--- | :--- | :--- | :--- |
| **AYA** | Electron + React | 内嵌 scrcpy (WebCodecs) | 易用美观，但 Electron 内存开销巨大（动辄 300MB+），AGPL-3.0 限制 | 汲取其 UI 布局分析交互，摒弃其 Web 臃肿技术栈 |
| **scrcpy** | C + SDL + FFmpeg | 官方低延迟投屏 | 极致轻量低延迟，但官方 GUI 简陋，缺乏多设备管理与工具箱 | 核心沿用其 Server 协议，由 Rust 直接承接视频流与控制 |
| **AndroMeld** | Android 14+ 专有 | 虚拟屏应用融合模式 | 可单独在 PC 打开单 App 独立窗口，体验惊艳，但仅支持单端 | **吸收其核心原理**：在 AnyDeck 中原生实现 Android 14+ 融合模式 |
| **QtScrcpy** | C++ + Qt | 原生 OpenGL 内嵌 | 性能极高，但 C++/Qt 跨平台 UI 开发效率低，难扩充复杂业务 | **采用 Flutter + Rust 异构架构**：兼具 Flutter 敏捷 UI 与 C/Rust 极致性能 |
| **go-ios** | Go + RemoteXPC | iOS USB 调试与投屏 | 攻克了 iOS 17+ 隧道难题，但缺乏现代化桌面交互界面 | **纳入底层驱动**：Rust 统一调度并接管其 MJPEG 视频流硬解码 |

---

## 3. 总体技术栈

| 层级 | 技术选择 | 选型职责与说明 |
| :--- | :--- | :--- |
| **UI 表现层** | Dart / Flutter Desktop | 跨平台桌面渲染（Canvas/CustomPaint）、多窗口（`desktop_multi_window`）、暗黑明亮主题与国际化 |
| **状态管理** | Riverpod 3.x | 管理设备列表、当前选中设备、Session 生命周期，与 UI 彻底解耦 |
| **底层核心** | Rust (`cdylib`) | 负责 Direct Socket、Tokio 异步并发、零拷贝字符解析、固定内存环形缓冲、USB 限流信号量 |
| **交互桥梁** | `dart:ffi` / NativePort | 高性能 C-ABI 跨语言绑定，仅传递纯数值结构体或内存指针，GC 开销降为零 |
| **Android 底座** | 自研 Rust Direct Socket | 直连 `127.0.0.1:5037`，彻底废除高频启动宿主机 `adb` 子进程的旧模式 |
| **鸿蒙底座** | Rust 管道池 + HDC 协议 | 托管系统 `hdc`，管理 `127.0.0.1:8710` 端口映射，无逆向维护风险 |
| **iOS 底座** | usbmuxd + BLE HID + WDA | 原生 Socket 识别设备；BLE 模拟官方鼠标实现免越狱免证书反控；WDA 负责批量脚本自动化 |

---

## 4. 总体分层架构 (DAL)

```text
lib/                                     rust/
  app/                                     device_bridge/
    router/ (GoRouter)                       src/
    theme/ (ThemeMode)                         adb_socket.rs (Direct ADB Client)
    l10n/ (AppLocalizations)                   performance.rs (零拷贝解析器)
  core/                                        logcat_ring.rs (20k 环形缓冲)
    dal/ (统一设备接口与模型)                   worker.rs (VideoToolbox 硬解)
    providers/ (Riverpod 全局状态)             hid_mouse.rs (iOS 蓝牙外设仿真)
  features/                                    core/
    overview/ (设备概览)                         driver.rs (DeviceDriver Trait)
    performance/ (性能监控折线图)                batch.rs (Tokio 并发限流引擎)
    fusion/ (Android 14 融合窗口)                android.rs / harmony.rs / ios.rs
    logcat/ (虚拟列表极速日志)               apk_inspector/ (离线秒级解包)
    processes/ (流式进程列表)
```

**核心设计约束**：
1. **UI 零拼接命令**：Flutter 绝不拼接 Shell 命令字符串，统一调用 Rust DAL 接口。
2. **零垃圾对象产生**：高频接口（性能、Logcat）禁止在 Dart 中生成大量瞬时 String/List，统一由 Rust 环形缓冲或结构体指针交付。
3. **USB 并发保护**：所有批量操作必须由 Rust `Arc<Semaphore>` 实施并发限流，保护主机 USB 控制器。

---

## 5. 核心服务接口设计

### 5.1 Rust 统一设备驱动 Trait (DeviceDriver)

```rust
#[async_trait]
pub trait DeviceDriver: Send + Sync {
    fn id(&self) -> &str;
    fn platform(&self) -> DevicePlatform;
    async fn execute_shell(&self, cmd: &str) -> Result<String, String>;
    async fn take_screenshot(&self) -> Result<Vec<u8>, String>;
    async fn push_file(&self, local: &str, remote: &str) -> Result<(), String>;
}
```

### 5.2 性能采样 C-ABI 接口

```rust
#[repr(C)]
pub struct PerformanceSnapshotFFI {
    pub cpu_usage: f32,
    pub used_memory_mb: f32,
    pub total_memory_mb: f32,
    pub fps: f32,
    pub battery_level: i32,
    pub is_charging: bool,
    pub uptime_secs: u64,
    pub core_count: u32,
    pub cores: [CoreUsageFFI; 16],
}

#[no_mangle]
pub extern "C" fn anydeck_poll_performance(
    serial: *const c_char,
    out_snapshot: *mut PerformanceSnapshotFFI,
) -> bool;
```

---

## 6. 投屏、应用融合与反向控制原理

### 6.1 Android 14+ 应用融合模式 (AndroMeld 模式)
- **底层原理**：Android 14 (API 34) 开放了 Shell 权限下的 `VIRTUAL_DISPLAY_FLAG_OWN_FOCUS` 与独立输入队列。
- **运行链路**：
  1. scrcpy-server 携带 `new_display=450x800/320 vd_system_decorations=false` 参数启动并生成新虚拟屏。
  2. 捕获系统分配的 `displayId`，执行 `am start --display <id> -n <App> -f 0x10000000` 将 App 投放到副屏。
  3. Flutter 开辟独立无边框子窗口（`desktop_multi_window`）渲染该视频纹理。
  4. 鼠标点击/滑动事件精准携带 `display_id` 注入，手机主屏可正常做其他操作，互不干扰。

### 6.2 iOS 投屏与双轨反向控制
- **投屏**：有线走 `go-ios` HTTP MJPEG 流，移交 Rust 提取 SOI/EOI 标记并通过 VideoToolbox 硬解码为 Metal 纹理；无线走 AirPlay 60 FPS 接收端协议。
- **日常反控（蓝牙 HID）**：电脑模拟为标准蓝牙鼠标（BLE HID Profile），iPhone 仅需开启“辅助触控”，光标毫秒级跟随，**无需任何证书与越狱**。
- **自动化反控（WDA）**：集成 WebDriverAgent HTTP 客户端，用于批量的绝对坐标点击与脚本录制回放。

---

## 7. 核心功能模块划分

### 7.1 Performance Tab (性能监控)
- **旧模式**：每秒 `Process.start` 启动 `adb` 并进行 Dart 正则拆词，内存持续膨胀。
- **新模式**：Rust 直接向 `127.0.0.1:5037` 发送复合指令，零拷贝切片原地计算 CPU 使用率与 FPS：
  $$\text{Usage}\% = \left(1 - \frac{\Delta \text{Idle}}{\Delta \text{Total}}\right) \times 100\%, \quad \text{FPS} = \frac{\Delta F}{\Delta t}$$

### 7.2 Logcat 实时日志引擎
- Rust 维持 Socket 长连接，维护 20,000 行定长环形内存队列，配合 SIMD 正则进行 Tag/PID/Level 过滤。
- Flutter 虚拟列表只按需拉取可视窗口（如当前视口的 30 行），实现十万行日志秒级刷屏不丢帧。

### 7.3 Layout Helper 与 UI 辅助
- 保持经典 Android 调试开关快速注入：`debug.layout`、暗黑模式、字体缩放、动画比例。
- 进阶能力：`uiautomator dump` XML 由 Rust 秒级扁平化解析，Flutter 原生绘制元素选框。

### 7.4 批量与定时自动化操作
- **批量并发控制**：基于 Tokio `JoinSet` + `Semaphore(4)`，支持 20 台设备同时执行 Shell、安装 APK、抓取截图，无惧 USB 汇流排被打崩。
- **定时任务引擎**：内置 Cron 调度器，支持夜间自动巡检、定时性能压测与报表导出。

---

## 8. 功能优先级与交付清单 (Feature Priorities)

| 优先级 | 模块 | 核心功能点 |
| :---: | :--- | :--- |
| **P0** | **Direct Socket 性能监控** | TCP 5037 直连、零拷贝 `/proc` 与 `dumpsys` 解析、单指针 C-ABI 更新、解决内存膨胀 |
| **P0** | **设备管理 (DAL)** | Android / 鸿蒙 / iOS 设备统一发现、心跳与详情注册表 |
| **P0** | **Android 投屏与控制** | Scrcpy 原生硬解（VideoToolbox）、键鼠映射、剪贴板无缝同步 |
| **P1** | **Android 14+ 融合模式** | 独立 VirtualDisplay 创建、单 App 任务定向投放、独立无边框子窗口、带 displayId 触控 |
| **P1** | **Logcat 原生环形引擎** | Rust 20k 行环形队列、SIMD 高速过滤、Flutter 视口虚拟渲染 |
| **P1** | **批量并发任务** | Tokio 并发分发、USB 信号量限流、批量安装 APK、批量 Shell 脚本 |
| **P2** | **iOS 投屏与反控** | USB MJPEG 硬解、蓝牙 BLE HID 鼠标免证书反控、WDA 自动化客户端 |
| **P2** | **鸿蒙 HDC 驱动集成** | 进程管道池托管、8710 端口转发、设备详情与文件传输 |
| **P3** | **AirPlay 无线镜像** | 电脑作为 AirPlay 接收端，实现 iOS 60 FPS 无线高清投屏 |
| **P3** | **定时自动化调度器** | Cron 定时任务引擎、巡检报表持久化存储 |

---

## 9. 演进路线图 (Roadmap)

- **Phase 1 (第 1 ~ 2 周)：基础破局与性能试点**
  - 在 `rust/device_bridge` 落地 `AdbSocketClient`。
  - 重构性能 Tab：接入 C-ABI 零拷贝结构体，验证内存下降 80%、子进程创建归零。
- **Phase 2 (第 3 ~ 4 周)：DAL 抽象、批量引擎与 Logcat**
  - 抽象 `DeviceDriver` Trait，封装 `AndroidDriver`。
  - 引入 Tokio 并发调度器与 USB 信号量限流（上限 4）。
  - 实现 Logcat 原生环形队列与视口渲染。
- **Phase 3 (第 5 ~ 7 周)：Android 14 融合模式与鸿蒙拉通**
  - 攻克 `new_display` 与 `displayId` 触控注入，跑通独立 App 桌面无边框子窗口。
  - 封装 `HarmonyDriver`，基于 HDC 管道接入鸿蒙设备控制。
- **Phase 4 (第 8 ~ 10 周)：iOS 投屏反控与无线自动化**
  - 落地 iOS 蓝牙 BLE HID 鼠标反控与 WDA 自动化客户端。
  - 集成 AirPlay 无线镜像与 Cron 定时调度器，全端稳定发布。

---

## 10. 风险点、兼容性与对策

| 风险类别 | 风险描述 | 架构对策 |
| :--- | :--- | :--- |
| **ADB 端口战争** | 若尝试自研替代 ADB Server，会与 Android Studio 互相 Kill 导致开发崩溃 | **坚守 Client 角色**：仅通过 Socket 连接官方 5037 端口，不篡位当 Server |
| **iOS 17+ 隧道变动** | 苹果废除旧端口，引入 CoreDevice QUIC/RemoteXPC 隧道，自研协议维护成本极高 | **借力成熟工具链**：Rust 调度并托管 `go-ios` 隧道，不从零逆向协议 |
| **鸿蒙协议演进** | HarmonyOS NEXT 版本迭代快，无稳定第三方 Rust Crate | **Rust 异步管道池调度**：利用 `tokio::process` 托管官方 `hdc` 二进制，流式接入数据 |
| **USB 汇流排崩溃** | 批量向 20 台设备并发传输大文件时，主板 USB Host Controller 容易过载断开 | **信号量限流机制**：严格通过 `Arc<Semaphore>` 限制底层并发连接数（默认 4） |
| **虚拟屏锁屏销毁** | 部分 Android ROM 在息屏时销毁 VirtualDisplay | 启动参数指定 `power_on=false`，并使用 KeepAlive 守护心跳 |
