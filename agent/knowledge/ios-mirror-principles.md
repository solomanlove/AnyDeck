# iOS 投屏与设备管理机制

本指南详细记录了 AdbManage（AnyDeck）项目中 iOS 设备集成、USB 投屏原理、状态同步以及相关自动化测试的设计原理。

---

## 1. 投屏机制（2026-10-06 更新）

macOS 已将原 `go-ios screenshot --stream` / MJPEG / `Image.memory` 投屏替换为 CoreMediaIO + AVFoundation + Flutter Texture。单张截图功能继续独立保留。视频不再占用固定 3333 端口，也不再按端口清理其他进程。

控制统一由主窗口持有 WDA Runner、iproxy USB 转发和 Session；模拟 BLE 已删除。当前面向 macOS + iPhone 6s 的实现、部署脚本、两个 PoC 的范围和未完成的真机验收见 [iOS 投屏控制](ios投屏控制.md)。不能将编译通过当作流畅度或真机控制已经通过。

---

## 2. 设备发现与状态管理 (Device Scan & State Management)

iOS 设备与已有的 Android ADB 心跳监测机制进行了无缝合并：

1. **自适应心跳轮询合并 (Heartbeat Integration)**：
   在 `AdbHeartbeatController` 中，除了通过 ADB 轮询 Android 设备外，还并发启动了 `IosDeviceService.listDevices()` 方法。
   - 使用 `go-ios list --details` 命令检索通过 USB 或网络连接且已与电脑配对的 iOS 设备。
   - 命令成功执行后，返回结构化的 JSON 列表。控制器提取 `Udid` 作为设备 ID，以及 `ProductName`、`ProductType`、`ProductVersion` 等属性。
   - 将 iOS 设备和 Android 设备统一拼装成 `List<AdbDevice>` 并向外派发。
   - Rust 与 CLI 共用 `IosDeviceIdentity` 型号和版本规范化：已知 `iPhone8,1` 显示 `iPhone 6s`，未知机型保留 ProductType；版本由 ProductVersion 直达设备列表并缓存，断开后仍可展示，不必先进入概览。注册表跳过 iOS 的 Android 元数据探测，详见 `devices_manager.md` 第 2.5 节。
   - **连接类型不能从 UDID 推断**：go-ios 的 `ConnectionType` 为 `USB` 或 `Network`（通常为 Wi-Fi），Rust FFI 透传为 `connection_type`。Dart 使用 `iosConnectionTypes` 集合合并同一 UDID 的多通道，不再遇到重复 UDID 就丢弃后续记录；心跳比较也包含通道变化。列表可同时显示 USB 与 Wi-Fi，侧栏同步展示；未知类型不冒充 USB，离线不保留在线通道。Android 的 TCP/TLS 标识不适用于 iOS。此字段表示可用通道，不保证某个 go-ios 命令实际选用哪条通道，命令仍使用 UDID。
   - 兼容旧 Rust 动态库：发现返回项缺少 `connection_type` 时，该服务实例后续直接使用 CLI 查询，避免旧库继续丢弃字段或每次心跳重复查询。
   - **多行 JSON 与警告信息容错**：由于 `go-ios list` 在部分环境下（如没有启动 tunnel 服务的 iOS 17+ 设备连接时）会在 stdout 首行输出警告日志 JSON，为了防止直接 `jsonDecode` 解析整段 stdout 时发生 `FormatException` 异常，`listDevices()` 采用 `LineSplitter.split` 将输出按行切分并逐行尝试 `jsonDecode` 解码。只有符合目标设备列表结构的 JSON 行才会被处理，其余警告行则会被安全忽略，保障了解析的高容错性。

2. **信息概览分流 (Overview Routing)**：
   当用户选中 iOS 设备进入“主页概览”时，由于 iOS 无法响应 ADB 的 `shell getprop` 指令，为了防止产生报错横幅（如 "adb已断开"），`deviceOverviewProvider` 增加了 `matchedDevice.isIos` 分支判定：
   - 绕过所有 Android `deviceInfoService` 逻辑。
   - 通过 `IosOverviewService` 并行读取 `ios info` 与 `ios diskspace`，构造 `brand: 'Apple'` 的 `DeviceOverview`，白名单缓存用于离线展示。详细字段与来源边界见第 11 节。

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
| 进程 | `ios ps --apps` / `ios kill --pid` | 展示进程与扩展，通过安装路径关联应用名称及 Bundle ID；结束进程需要确认 |
| 截图 | `ios screenshot --output=<file>` | 缺少开发者镜像时自动挂载并重试一次；使用临时目录，结束后删除临时文件 |
| UI 自动化 | 主窗口 WDA HTTP Session + `ios runwda` + `iproxy` | 先签名安装 Runner，界面启用控制后托管启动/转发；详见 iOS 投屏控制 |

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

## 10. iOS 进程详情与应用关联（2026-10-05）

### 字段及关联机制

此前进程解析仅读取小写 `name` 等字段，而当前 go-ios 真机结果使用 `Name`，导致页面全部回退为 `PID xxx`。

- `IosProcessParser` 统一读取 `Name`、`Pid`、`RealAppName`、`StartDate`、`IsApplication`，兼容旧字段及名称/PID 映射。忽略日志、包装对象中的计数和进程内部元数据，未知日期不展示。
- `IosAppInfo.path` 保留 `ios apps --all` 返回的安装目录 `Path`，`copyWith` 更新图标时继续保留该字段。
- `IosCommandService.listProcesses` 每次先查询进程，非空时再查询一次同 UDID 的应用列表，按目录建立索引。每条命令沿用 15 秒超时，无按进程逐个查询或后台轮询。
- 使用可执行路径最外层 `.app/` 目录匹配安装路径；统一 `/private/var/` 与 `/var/`，使用 POSIX 路径语义，不受桌面宿主系统影响。匹配不到时，主进程可使用明确返回的 Bundle ID 关联；不按名称猜测，避免多个 Flutter `Runner` 误匹配。
- `.appex/` 路径标识 App Extension，其所属应用保存在 `IosProcessInfo.app`；进程自身的 `bundleId` 独立保留。页面对扩展关联结果标注“宿主 Bundle ID”，不把宿主 ID 当作扩展自身 ID，也不根据通用进程名称推测扩展具体类型。
- 应用查询失败仅记录警告并回退到原始进程信息，不使整个进程列表失效。没有可靠关联时不伪造应用名称或 Bundle ID。

### 页面与安全边界

- `IosProcessTile` 独立承接展示：应用名与进程名、可复制 Bundle ID、PID、App/Extension 类型、系统/用户应用类别、版本、主机本地时区的启动时间以及带完整路径 Tooltip 的单行路径。
- 中英文文案放在 `app_l10n_ios_tools.dart`；沿用主题颜色和虚拟列表，不引入额外依赖。
- 设备切换时清除旧列表，使用请求序号隔离迟到结果。结束进程的确认框展示应用与进程名称，操作绑定原设备 UDID 和请求序号；切换设备后旧确认不得结束新设备进程。
- 本次没有加入 CPU/内存采样，也没有修改 Android/HarmonyOS 进程或 iOS 投屏、截图链路。

### 验证记录与待验收项

针对性测试共 32 项通过，包含 1 项显式启用的真机只读查询；相关 9 个 Dart 文件静态检查无问题。覆盖真实字段结构、宿主/扩展 ID 区分、同名 Runner 路径隔离、路径别名、应用查询失败降级、切换设备的迟到结果、中英文窄屏明暗主题，以及既有应用和截图回归。

```bash
flutter test test/ios_process_info_test.dart test/ios_processes_tab_test.dart test/ios_command_service_test.dart test/ios_apps_tab_test.dart test/ios_screenshot_capture_test.dart
# 显式指定 UDID 才额外执行真机用例，不会结束任何设备进程。
flutter test --dart-define=IOS_PROCESS_UDID=<UDID> test/ios_process_info_test.dart
```

当前连接 iPhone 的实际进程已通过新服务读取出名称，并成功关联应用 Bundle ID。未启动桌面项目，完整桌面交互、真实结束进程、断连及 iOS 17+ 设备仍需手动验收。

## 11. iOS 概览信息读取（2026-10-06）

### 数据与展示

此前 iOS 分支只把设备列表中的系统版本填入概览，其余字段固定为 `-`，还将 UDID 显示为序列号、把固定的 `Darwin` 显示为内核版本。本次改为以下数据来源：

| 字段 | 来源与边界 |
| --- | --- |
| 设备名、型号、序列号 | `DeviceName`、`ProductType`、`SerialNumber`；保留用户自定义别名，UDID 只用于命令路由 |
| 系统、CPU | `ProductVersion`、`BuildVersion`、`HardwareModel`、`CPUArchitecture`、`instruments:hardwareInformation.numberOfCpus` |
| 存储 | `diskspace.TotalBytes/FreeBytes`；按十进制 GB 显示已用/总量，拒绝负数、零总量、剩余大于总量等无效数据 |
| 网络 | `instruments:networkInformation` 展示接口清单，`WiFiAddress` 标为硬件 MAC；接口存在不代表已连接某个 SSID |
| 屏幕与芯片规格 | `IosModelSpec` 目前仅收录已核对的 `iPhone8,1`（iPhone 6s、A9、750 × 1334、326 PPI），明确标注“型号规格”；未知型号保留 ProductType，不套用该规格 |
| 暂无读数 | 实时 RAM、内核版本、SSID/IP、逻辑分辨率、scale、刷新率显示“暂未读取”；不把 PPI 解释为 Android 逻辑密度 |

规格来源：[Apple iPhone 6s 技术规格](https://support.apple.com/en-us/111952)。后续扩充型号需要核对来源；静态规格不作为实时读数写入通用分辨率字段。

### 实现与生命周期

- `core/ios/ios_overview_service.dart` 并行执行两条定向 UDID 的只读短命令，沿用 `IosCommandService.run` 的 15 秒超时及进程回收；无后台采样、自动挂载或常驻 tunnel。
- 解析兼容 WARN 前缀、单行和格式化 JSON；必须识别目标数据对象。单项失败保留其它可用字段并显示部分读取失败提示，不伪造容量或序列号。
- `IosOverviewDetails` 仅保存型号、Build、硬件型号、CPU 核心数、接口与部分失败状态；缓存不保存 lockdown 原始对象、IMEI、NonVolatileRAM 或配对信息。
- `deviceOverviewProvider` 接入读取和缓存，失效后重新获取；异步返回检查 `ref.mounted`，不会将旧 Provider 结果写入当前视图。离线复用既有 `cachedDeviceOverviewProvider`。
- iOS 详情字段与通用详情生成拆到独立 overview part 文件，共用卡片和响应式布局，补齐中英文；Android/HarmonyOS 详情逻辑保持原样。

### 验证记录

21 项针对性测试通过，覆盖数据解析、无效容量、部分失败、缓存白名单与兼容、Provider 刷新及别名保留、iOS 中英文宽窄屏、明暗主题，以及原 Android 概览布局/模型回归。布局测试补齐 Root Provider mock，避免真实设备查询及未结束 Timer 干扰。

```bash
flutter test test/ios_overview_service_test.dart test/ios_overview_layout_test.dart test/overview_layout_test.dart test/device_overview_test.dart
# 只有显式提供 UDID 才执行真机只读用例。
flutter test --dart-define=IOS_OVERVIEW_UDID=<UDID> test/ios_overview_service_test.dart
```

相关 12 个文件针对性 analyze 通过。额外检查 `dashboard_screen.dart` 时存在原有 `liquid_glass_background.dart` 未使用 import 警告，本次未改动。2026-10-05 已验证设备原始命令可读出上述身份、存储、CPU、接口字段；2026-10-06 收尾时 `ios list --details` 为空，因此新服务真机用例未执行。未启动桌面项目；真机刷新、离线显示及 iOS 17+ 环境仍待设备验收。
