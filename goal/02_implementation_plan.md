# 详细落地实施计划与演进路线图 (Implementation Plan)

本文档明确 AnyDeck 底座重构与多端能力建设的四个阶段（Phase 1 至 Phase 4）、里程碑周期、任务拆解及验收量化标准。

---

## 一、阶段里程碑规划总览

```text
[ Phase 1: 性能破局与 Direct Socket 试点 ] (第 1 ~ 2 周)
  └── 核心目标: 解决性能 Tab 宿主机进程与 Dart GC 痛点，跑通 Rust Direct Socket 与 C-ABI 零拷贝。

[ Phase 2: 统一抽象层 (DAL) 与批量调度引擎 ] (第 3 ~ 4 周)
  └── 核心目标: 抽象 DeviceDriver Trait，引入 Tokio 与 Semaphore 限流，落地 Logcat 原生环形队列。

[ Phase 3: Android 14 融合模式与鸿蒙拉通 ] (第 5 ~ 7 周)
  └── 核心目标: 实现单 App 独立窗口虚拟屏投屏 (AndroMeld 模式)；将鸿蒙 HDC 纳入统一控制流。

[ Phase 4: iOS 投屏反控与无线自动化生态 ] (第 8 ~ 10 周)
  └── 核心目标: 落地 iOS 蓝牙 HID 鼠标反控 + WDA 自动化，集成 AirPlay 无线镜像，全端正式交付。
```

---

## 二、各阶段详细任务拆解

### 阶段一：性能破局与 Direct Socket 试点 (Week 1 ~ Week 2)

- [ ] **任务 1.1：Rust 侧 Direct ADB Socket 客户端实现**
  - 在 `rust/device_bridge/src/` 中新增 `adb_socket.rs`。
  - 实现基于 `std::net::TcpStream` 的标准 AOSP 4 字节 Hex 长度帧封包与解包。
  - 支持连接 `127.0.0.1:5037`、发送 `host:transport:<serial>` 及 `shell:<command>`。
- [ ] **任务 1.2：Rust 零拷贝性能解析器与差值算法**
  - 在 Rust 侧实现 `PerformanceParser`，利用切片（`&[u8]`）直接解析 `/proc/uptime`、`dumpsys battery`、`/proc/meminfo`、`/proc/stat` 与 `dumpsys gfxinfo`。
  - 维护前置时间片与帧数计数器，在 Rust 原生原地计算 CPU 使用率与实时 FPS。
- [ ] **任务 1.3：C-ABI 结构体定义与 FFI 对接**
  - 定义 `PerformanceSnapshotFFI` 紧凑定长结构体，导出 `anydeck_poll_performance`。
  - 在 Dart 侧封装 `RustPerformanceBridge`，直接读取 Native 结构体更新 UI。
  - 彻底废除旧的 `_unifiedCommand` 与 Dart 正则拆词解析。

### 阶段二：统一抽象层 (DAL) 与批量并发引擎 (Week 3 ~ Week 4)

- [ ] **任务 2.1：DeviceDriver Trait 架构确立**
  - 在 Rust Core 中定义统一的 `DeviceDriver` Trait 与枚举类型（Android / Harmony / iOS）。
  - 将阶段一的 Android 能力封装为 `AndroidDriver` 实现。
- [ ] **任务 2.2：Tokio 异步运行时与批量调度器 (BatchManager)**
  - 引入 `tokio` 异步框架，基于 `JoinSet` 实现并发任务分发。
  - 增加 `Arc<Semaphore>` 限制 USB 总线最大并发数（默认 4），防止批量文件读写导致 USB 控制器挂死。
- [ ] **任务 2.3：Logcat 原生定长环形队列与 SIMD 过滤**
  - Rust 维护固定大小（20,000 行槽位）的原生环形缓冲区（Ring Buffer）。
  - 实现 Tag/PID/Level 的极速过滤，通过 FFI 提供虚拟视口查询接口（如查询当前可见的 30 行）。

### 阶段三：Android 14 融合模式与鸿蒙 HDC 接入 (Week 5 ~ Week 7)

- [ ] **任务 3.1：scrcpy 虚拟屏启动与 Display ID 获取**
  - 在 `rust/device_bridge/src/adb.rs` 中为 scrcpy-server 追加 `new_display` 与 `vd_system_decorations=false` 参数。
  - 解析握手报文，捕获由 Android 14 系统动态分配的 `displayId`。
- [ ] **任务 3.2：任务定向投放与桌面独立子窗口构建**
  - 通过 ADB Shell 发送 `am start --display <displayId> -n <Component>`。
  - 利用 `desktop_multi_window` 创建以目标 App 命名的独立无边框 Flutter 窗口。
- [ ] **任务 3.3：带 display_id 的触控与按键注入**
  - 扩展 `anydeck_send_control` 报文，加入 `display_id: u32` 字段。
  - 注入鼠标点击、拖拽、滚轮与物理键盘字符，确保事件仅在虚拟屏生效。
- [ ] **任务 3.4：鸿蒙 HDC 驱动集成**
  - 封装 `HarmonyDriver`，基于 `tokio::process` 接入官方 `hdc` 进程管道。
  - 实现设备发现、Shell 执行、文件传输与 `hdc fport` 视频流转发。

### 阶段四：iOS 投屏反控与无线自动化生态 (Week 8 ~ Week 10)

- [ ] **任务 4.1：iOS 视频流解码下沉**
  - 将 `go-ios` HTTP MJPEG 流移交 Rust 提取 SOI/EOI 标记，通过 VideoToolbox 硬解码为原生 Metal 纹理渲染。
- [ ] **任务 4.2：蓝牙 BLE HID 鼠标与键盘虚拟仿真**
  - 在 Rust 侧调用 macOS `CoreBluetooth Peripheral` / Windows BLE API，将电脑对外广播为标准蓝牙鼠标。
  - 投屏窗口捕获鼠标移动和点击，转换为主流 HID Report 实时无线注入 iPhone 辅助触控。
- [ ] **任务 4.3：WebDriverAgent (WDA) 自动化接口集成**
  - 封装轻量级 WDA HTTP Client，支持批量坐标点击、手势滑动与文本输入。
- [ ] **任务 4.4：AirPlay 接收端与定时调度器**
  - 集成轻量级 AirPlay 协议接收端，支持局域网 60 FPS 无线低延迟镜像。
  - 实现 Cron 定时调度器，支持预设定时性能巡检与自动化任务。

---

## 三、量化验收指标 (Acceptance Metrics)

| 验收维度 | 优化前 (现状) | 阶段一预期 | 最终目标 (阶段四) |
| :--- | :--- | :--- | :--- |
| **性能监控内存占用** | 随时间持续上涨至 150MB+ | 稳定在 $< 35\text{MB}$ | 稳定在 $< 25\text{MB}$ |
| **宿主机 CPU 占用** | 周期性脉冲达 15%~25% | 稳定在 $< 1.0\%$ | 稳定在 $< 0.5\%$ |
| **进程创建数** | 1 次/秒 (每小时 3600 次) | 0 次/秒 (长连接维持) | 0 次/秒 |
| **Logcat 列表滑动帧率** | 大量日志时掉帧至 20~30 FPS | - | **恒定 60 FPS 无丢帧** |
| **Android 14 融合模式** | 不支持 | - | **单个 App 独立无边框运行，手机可正常锁屏** |
| **iOS 鼠标反控延迟** | 不支持 | - | **$< 15\text{ms}$ (蓝牙 HID 物理级响应)** |
| **批量任务稳定性** | 并发 5 台以上偶发 USB 掉线 | - | **20 台设备批量任务无掉线 (信号量限流)** |
