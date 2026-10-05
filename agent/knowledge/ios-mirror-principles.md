# iOS 投屏与设备管理机制

本指南详细记录了 AdbManage（AnyDeck）项目中 iOS 设备集成、USB 投屏原理、状态同步以及相关自动化测试的设计原理。

---

## 1. 投屏机制 (USB Mirroring Principle)

iOS 投屏在本项目中采用 **USB 本地端口转发** 与 **MJPEG 图像流解析** 方案，摆脱了对 Android-scrcpy 编解码体系的依赖，保持极轻量化：

1. **go-ios screenshot 端口转发**：
   通过 `go-ios screenshot --stream --port=[port] --udid=[udid]` 指令启动 iOS 截图流服务。该服务会建立 USB 连接通道，在指定的本地 TCP 端口（如 `127.0.0.1:port`）启动一个轻量级的 HTTP MJPEG 服务。

2. **纯 Dart 缓冲区包分包解析 (SOI/EOI Boundary Parsing)**：
   iOS 投屏的渲染并不依赖 GStreamer 或 FFmpeg 库，而是通过纯 Dart 代码高效率提取 JPEG 帧：
   - 建立 `HttpClient` 连接到本地 HTTP Stream，接收流式的二进制数据块。
   - 每接收到一个 Chunk，将其追加到内存缓冲区。
   - 检索 JPEG 协议的文件起始标记 **SOI (`0xFF, 0xD8`)** 与文件结束标记 **EOI (`0xFF, 0xD9`)**。
   - 一旦定位到完整的 SOI 到 EOI 字节区间，即截取出一个完整的 JPEG 帧，使用 `Image.memory` 原生 Widget 快速渲染（同时使用 `gaplessPlayback: true` 消除闪烁）。
   - 移除已处理字节，循环检索后续帧，防止缓冲区膨胀。

---

## 2. 设备发现与状态管理 (Device Scan & State Management)

iOS 设备与已有的 Android ADB 心跳监测机制进行了无缝合并：

1. **自适应心跳轮询合并 (Heartbeat Integration)**：
   在 `AdbHeartbeatController` 中，除了通过 ADB 轮询 Android 设备外，还并发启动了 `IosDeviceService.listDevices()` 方法。
   - 使用 `go-ios list --details` 命令检索已通过 USB 连接并信任电脑的 iOS 设备。
   - 命令成功执行后，返回结构化的 JSON 列表。控制器提取 `Udid` 作为设备 ID，以及 `ProductName`、`ProductType`、`ProductVersion` 等属性。
   - 将 iOS 设备和 Android 设备统一拼装成 `List<AdbDevice>` 并向外派发。
   - **多行 JSON 与警告信息容错**：由于 `go-ios list` 在部分环境下（如没有启动 tunnel 服务的 iOS 17+ 设备连接时）会在 stdout 首行输出警告日志 JSON，为了防止直接 `jsonDecode` 解析整段 stdout 时发生 `FormatException` 异常，`listDevices()` 采用 `LineSplitter.split` 将输出按行切分并逐行尝试 `jsonDecode` 解码。只有符合目标设备列表结构的 JSON 行才会被处理，其余警告行则会被安全忽略，保障了解析的高容错性。

2. **信息概览绕过 (Overview Bypass)**：
   当用户选中 iOS 设备进入“主页概览”时，由于 iOS 无法响应 ADB 的 `shell getprop` 指令，为了防止产生报错横幅（如 "adb已断开"），`deviceOverviewProvider` 增加了 `matchedDevice.isIos` 分支判定：
   - 绕过所有 Android `deviceInfoService` 逻辑。
   - 直接根据设备注册表中的内存缓存（UDID、ProductName、ProductVersion）构造并 `yield` 一个静态的 `DeviceOverview` 对象（其中 `brand: 'Apple'`），确保页面零加载延迟且没有任何 ADB 报错。

---

## 3. 多窗口 Isolate 隔离状态同步 (Multi-Isolate Argument Binding)

在多窗口环境下，每个独立投屏窗口属于一个全新的 Isolate 线程。

- **竞态条件 (Race Condition)**：
  在子 Isolate 启动时，主 Isolate 中的 `deviceRegistryProvider` 未必已经全量同步至内存（SharedPreferences 的异步加载可能存在数百毫秒延迟）。如果在子窗口中仅通过 `deviceId` 到 `deviceRegistryProvider` 同步去查 `isIos` 状态，极有可能在首帧将该 iOS 设备错判为 Android，并试图拉起 Scrcpy，从而导致投屏失败。
- **解决方案 (Explicit Arguments)**：
  在主窗口点击投屏按钮时，调用 `openStandaloneMirrorWindow` 方法，在该方法中直接提取当前已知的 `device.isIos` 参数，并通过窗口参数 `'isIos': device.isIos` 显式随 `createAdbManageWindow` 传入。子窗口直接从参数中加载 `isIos` 标记实例化 `MirrorWindowController`，彻底杜绝了同步竞态。

---

## 4. 子 Isolate 状态保活 (Sub-Isolate Online Keeper)

- **心跳禁用与保活**：
  为节省 CPU 消耗，子 Isolate（独立投屏窗口）内不运行任何 ADB/iOS 设备插拔的心跳轮询，而是通过 `deviceOnlineProvider` 的 `isSub` 机制监听当前是否有处于活跃状态的投屏 Session。
- **双通道判定 (Dual-Channel Check)**：
  在此前的判定中，仅检查了 Scrcpy 的 `activeEmbeddedMirrorProvider`。对于 iOS，必须检查 `activeIosMirrorProvider(deviceId) != null`。我们将其升级为双通道检测：
  ```dart
  if (isSub) {
    return ref.watch(activeIosMirrorProvider(deviceId)) != null ||
        ref.watch(activeEmbeddedMirrorProvider(deviceId)) != null;
  }
  ```
  这保证了在子窗口中，iOS 投屏的在线状态检测能返回 `true`，防止子窗口刚启动就被判定为离线而关闭投屏。

- **子窗口投屏激活状态与 iOS 分支判定 (Active Mirror State Checking)**：
  在子窗口组件 `MirrorWindowContent` 构建核心渲染视图时，需要通过 `isMirrorActive` 字段来确定投屏会话是否已建立。
  由于子 Isolate 状态不同步，此处同样不能从 `deviceRegistryProvider` 同步检索 `isIos` 标记，否则会导致投屏虽已建立但 UI 错误显示“未连接或投屏已停止”。
  解决方法是结合传递参数 `widget.isIos` 以及 UDID 格式降级探测来最终确定是否为 iOS：
  ```dart
  final isIos = widget.isIos ||
      (widget.deviceId.length == 40 && !widget.deviceId.contains(RegExp(r'[^a-fA-F0-9]'))) ||
      (widget.deviceId.length == 25 && widget.deviceId.indexOf('-') == 8);
  ```
  然后再根据该标志位分别监视 `activeIosMirrorProvider` 或 `activeEmbeddedMirrorProvider`，确保 UI 状态能够无竞态、高可靠地衔接。

---

## 5. 自动化测试与 Mock 设计 (Widget Test Mocking)

为了在没有连接苹果物理机、或者没有全局安装 `go-ios` 工具链的集成/测试环境中安全运行测试：

- **IosDeviceService Mock**：
  由于心跳模块 `AdbHeartbeatController` 依赖 `IosDeviceService` 去获取设备状态，在 Widget 测试中，为了防止真实的 `Process.run('ios', ...)` 造成 `pumpAndSettle timed out` 悬挂超时，我们在 `test/widget_test.dart` 中实现并注入了 `FakeIosDeviceService`：
  ```dart
  class FakeIosDeviceService extends IosDeviceService {
    @override
    Future<List<AdbDevice>> listDevices() async => [];
  }
  ```
  在测试的 `ProviderScope` 的 `overrides` 中注入该模拟服务，阻断了对真实进程命令的调用，确保测试能瞬间跑通。

---

## 6. go-ios 设备工具能力

除投屏外，项目通过 `IosCommandService` 集中提供以下能力，UI 不直接启动外部进程：

| 功能 | go-ios 命令 | 边界 |
| --- | --- | --- |
| 应用列表 | `ios apps --all --udid=<UDID>` | 同时解析用户与系统应用 |
| 安装/卸载 | `ios install` / `ios uninstall` | IPA 必须已正确签名；卸载需要用户确认 |
| App 文件 | `ios fsync --app=<BundleID>` | 仅限允许访问的 App container，不提供 iOS 全盘文件系统 |
| 系统日志 | `ios syslog --parse` | 长生存期进程由页面持有并在 dispose 时终止 |
| 进程 | `ios ps --apps` / `ios kill --pid` | 默认只展示 App 进程，结束进程是有副作用操作 |
| 截图 | `ios screenshot --output=<file>` | 缺少开发者镜像时自动挂载并重试一次；使用临时目录，结束后删除临时文件 |
| UI 自动化 | `ios ui ... --driver=wda` | 依赖已经签名、安装并启动的 WebDriverAgent |

所有命令参数都通过 `Process.start(executable, args)` 的参数列表传入，不经过 shell 拼接。短命令默认 15 秒超时，IPA 和文件传输使用 5 分钟超时；超时后先普通终止，再以 `SIGKILL` 兜底。`--text` 的用户输入在全局日志中必须脱敏。

## 7. UI 与生命周期

iOS 在线设备开放“控制、应用、进程、文件、日志、截图”六个入口：

- 控制页提供 WDA 状态、UI Tree、坐标点击、滑动、文字输入和按键操作。
- 系统日志最多保留 3000 行，通过 100ms batch 降低 Riverpod/Widget rebuild 频率，使用 `ListView.builder` 虚拟化渲染。
- 截图复用 Dashboard 截图页，但隐藏 Android `screenrecord` 按钮；iOS 当前没有通过 go-ios 输出带音频的视频流。
- iOS 切换到未支持的 Terminal、Web、Layout、Performance、Network Tab 时回退到概览页。

## 8. 测试与回归范围

1. USB 和 Finder Wi-Fi 两种 transport 分别验证应用列表、进程列表、截图和 syslog。
2. 使用已签名 IPA 验证安装、刷新列表、卸载确认和卸载后刷新。
3. 使用开启 File Sharing 的测试 App 验证 `tree`、`push`、`pull`；无权限 App 应显示 go-ios 原始错误。
4. 启动日志后切换 Tab、切换设备和关闭窗口，确认 `ios syslog` 不残留。
5. WDA 未部署时应显示明确错误；部署完成后验证 UI Tree、tap、swipe、type 和 home button。
6. Android 与 HarmonyOS 的原有 Tab、ADB/HDC 命令和截图录屏路径必须保持不变。

## 9. 截图缺少 Developer Disk Image 的自动恢复（2026-10-05）

### 问题与实现

截图页通过 `IosCommandService.captureScreenshot` 执行一次性截图，此前没有投屏入口中的镜像挂载恢复流程。未挂载时，go-ios 会返回 `DVTSecureSocketProxy` / `InvalidService` 或 `Developer Disk Image must be mounted`，页面直接展示失败。

- `lib/core/ios/ios_screenshot_capture.dart` 独立承接截图恢复，复用 `IosCommandService.run` 的参数列表、超时和进程回收机制。
- 先正常截图；只有明确的镜像未挂载或截图开发服务 `InvalidService` 错误才执行 `ios image auto --udid=<UDID>`，成功后重试截图一次。重试失败直接返回，不递归挂载。
- 普通截图仍为 15 秒超时；镜像首次下载和挂载允许 5 分钟，超时由执行器终止进程。不会启动常驻 tunnel，也不会修改全局环境变量。
- 同一个服务实例内按 UDID 共享进行中的截图 Future，避免连续截图或重复刷新并发挂载；结束或失败后移除记录，下一次可重新尝试。
- 失败重试前删除旧输出；最终检查截图文件存在且非空，成功或异常均清理临时目录。
- 命令退出码为 0 时同时检查 stdout/stderr 中的 ERROR/FATAL JSON。截图错误优先提取 `err`/`error`/`msg`，避免 stdout 的 WARN 遮蔽 stderr 的真正原因；原始 stdout/stderr 仍保留在 `AdbResult` 中。

当前连接设备经 `ios list --details` 确认为 iOS 15.8.8。`go-ios agent is not running ... ios17+` 为通用警告，不能仅根据这条 WARN 判断当前设备必须启动 tunnel。iOS 17+ 的开发服务仍需环境中已有可用 tunnel，自动启动该服务不在本次修复范围。[go-ios 官方说明](https://github.com/danielpaulus/go-ios)

### 验证与回归边界

已通过以下针对性验证，未启动桌面项目：

```bash
flutter test test/ios_screenshot_capture_test.dart test/ios_command_service_test.dart test/ios_device_service_test.dart
flutter analyze lib/core/ios/ios_command_service.dart lib/core/ios/ios_screenshot_capture.dart test/ios_screenshot_capture_test.dart
```

- 16 项测试通过，覆盖正常截图、挂载恢复、挂载失败、有限重试、警告/断连不误触发、缺失文件、临时目录清理、同设备并发合并、失败后重新请求及 stderr ERROR 识别。
- 使用当前已连接的 iOS 15.8.8 真机执行可选测试，修改后的服务成功返回截图字节，并由 Flutter 解码验证宽高大于 0。测试不保存截图内容。
- 真机用例仅显式指定 UDID 后启用，常规测试不会访问设备：

```bash
flutter test --dart-define=IOS_SCREENSHOT_UDID=<UDID> test/ios_screenshot_capture_test.dart --plain-name '真机截图字节可以被 Flutter 解码'
```

仍需手动验证桌面截图页刷新、连续截图、锁屏/拔线和 iOS 17+ tunnel 场景；本次未对这些场景作 UI 验收。Android/HarmonyOS 截图与录屏路径、投屏会话、主题及跨窗口通信均无修改。
