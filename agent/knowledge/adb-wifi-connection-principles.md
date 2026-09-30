# ADB over Wi-Fi 调试连接原理与集成机制

## 1. 当前设备行连接流程（2026-09-30）

Android 实体手机的 USB 自动准备、设备行连接 icon、二维码 / 配对码连接统一接入 `AdbWirelessCoordinator`。通用手动地址弹窗和 HarmonyOS HDC 保留原有入口。

| 场景 | 执行过程 |
| --- | --- |
| USB 授权上线 | `get-state` 确認 `device` → 获取物理 serial → 检查 `service.adb.tcp.port` → 未监听 5555 时执行 `tcpip 5555` → 等待 2 秒 → 就绪检测与实时 IP 探测 → icon 可点击 |
| 点击连接 icon | 等待本机自动准备完成 → 在线 USB 刷新监听及 IP / 在线网络通道刷新 IP → `connect IP:5555` → 回读 `get-state` 和物理 serial |
| TCP 连接失败 | 显示 mDNS 查找进度 → 发现目标手机 → 优先 `_adb._tcp`，再尝试 `_adb-tls-connect._tcp` → 连接后校验硬件身份 |
| 已通过 TLS 连通 | 先保存实时 Wi-Fi IP → 开启传统 5555 监听 → 等待 2 秒 → 重试 TCP 连接 → 在线和身份确认后刷新 IP、断开已知的同机 TLS transport |
| 切换 TCP 失败 | 尝试恢复原 TLS 地址；若动态端口改变，重新读取 mDNS 并校验目标身份 → 展示“暂时使用无线调试连接”或恢复失败提示 |
| 配对码 / QR | 配对成功后最多 5 轮查找该 IP 的 TLS **连接端口** → 同一 TCP 优先编排；不把配对端口或 5555 当成 TLS 连接端口 |

- 2 秒为工程默认等待值，不是 Android 的固定保证。服务已经监听 5555 时跳过重启和初始等待。
- 重启后准备 / 切换的检测窗口为 10 秒，轮询间隔 500ms；普通探测命令超时 3 秒，就绪检测单次不超过 2 秒且受剩余预算限制；配对命令超时 15 秒。整条含发现、恢复流程会比 10 秒长。
- USB 上线只准备监听和 IP，不自动建立 TCP transport；点击 icon 才连接。
- mDNS 回退只在此次连接操作内进行，最多 3 轮，不增加永久轮询进程。传统 ADB Server 自身的自动发现机制独立存在。
- 只有在线 Android 实体 USB 才自动准备；排除 iOS、HDC、`emulator-*`、`unauthorized` 和 `offline`。
- 主窗口独占准备操作；子窗口不会重启 `adbd`。各设备任务进入串行队列，同设备并发点击合并处理。
- `adbd` 重启可能造成短暂离线，USB 离线采用 15 秒去重宽限；长时间断开后允许再次准备。元数据探测等待正在进行的 USB 准备结束。

## 2. IP、身份与连接判定

### 2.1 实时 IP

Android 连接准备不读取旧 Overview IP，依次使用：

```bash
adb -s <device_id> shell ip -4 route
adb -s <device_id> shell ip -o -4 addr show
```

只匹配 `wlan*`、`wifi*`、`swlan*` 接口，优先取路由的 `src` 字段，避免误选默认网关、VPN 或蜂窝地址。地址探测失败不会把任意接口地址当作 Wi-Fi IP；非常规 ROM 接口名需要后续根据真机输出扩展。当前自动流程支持 IPv4。

实时结果回写现有注册表和 SharedPreferences；USB 准备未获取到 IP 时清除旧地址展示。注册表异步加载磁盘缓存时保留较新的连接结果，防止 DHCP 地址被旧快照覆盖。

### 2.2 身份与 mDNS

- 优先 `ro.serialno`，其次 `ro.boot.serialno`；USB transport ID 与硬件 serial 不同的设备也可连接。
- mDNS 实例解析支持名称中的空格，例如 `adb-PHONE-abc (2)`；只解析传统连接和 TLS 连接服务，忽略配对服务。
- 通过实例名前缀完整匹配目标 serial，或通过完整 IP 匹配候选；连接后仍必须校验 serial，不能仅凭旧 IP 自动对其他手机执行 `tcpip`。
- 身份校验失败时，只清理由本次操作新建的错误 transport，不断开原先已在线的其他设备。
- 未知身份的离线历史设备提示先接 USB 或使用配对入口，不自动扫描并控制其他手机。
- mDNS 发现不代替配对授权；TLS 回退要求手机已开启无线调试且电脑具备有效信任关系。

### 2.3 成功与失败

`adb connect` 退出码为 0 不代表设备可用。新流程以目标 `get-state == device` 且硬件身份匹配为成功条件；Ping 不再作为 Android 设备行连接的前置门槛。

状态和失败原因以本地化 key 提供给 UI，覆盖授权、监听失败、无 IP、身份不符、发现失败、配对失败、TLS 回退与恢复失败。操作期间两个连接入口共享 Loading / 禁用状态；自动准备失败也在设备行显示原因。

## 3. 通道优先级与系统边界

- 同一物理设备存在多个通道时，命令路由保持 `USB > 传统 TCP/IP 5555 > TLS 无线调试`。
- mDNS `_adb-tls-connect._tcp` 服务名明确按 TLS 识别，不再误判为传统 TCP，也不从实例名构造伪 IP；`_adb._tcp` 按传统 TCP 识别。没有服务类型信息的数字地址沿用 5555 / 非 5555 的兼容分类。
- `tcpip` 会重启手机 `adbd`，可能打断该机已有 scrcpy、Shell、文件传输；准备前检查当前监听避免不必要的重复重启。不修改投屏协议或全局 ADB Server，不关闭手机无线调试设置。
- TCP 成功后，只断开已知且再次确认属于该机的 TLS transport；共享 ADB Server 或其他工具可能重新自动连接 TLS。不能保证通知栏图标消失，实际行为需要按 ROM 真机验收。
- `adb disconnect` 只断开 transport，并不关闭监听。停止监听需在有效通道执行 `adb -s <id> usb`，或重启手机。

## 4. 源码、验证与交接

| 文件 | 职责 |
| --- | --- |
| `lib/core/adb/wireless/adb_wireless_coordinator.dart` | 串行任务、USB 去重、TCP 优先、mDNS 回退、TLS 切换恢复与取消 |
| `lib/core/adb/wireless/adb_wireless_probe.dart` | 有界 ADB 命令、在线 / serial 校验、实时 Wi-Fi IP 解析 |
| `lib/core/adb/wireless/adb_wireless_state.dart` | 状态、可本地化结果、mDNS 解析和连接 ID 分类 |
| `lib/core/providers/modules/wireless_connection_provider.dart` | 主窗口生命周期与按设备可订阅进度 |
| `lib/core/providers/modules/device_registry_providers.dart` | 设备上线入口、IP 缓存回写、统一配对和连接入口 |
| `lib/core/providers/modules/device_registry_probe_service.dart` | 元数据 IP 探测复用实时查询 |
| `lib/core/providers/modules/registered_device_model.dart` | 服务名分类、有效 IPv4 与优先命令 ID |
| `lib/features/devices/widgets/device_wireless_controls.dart` | 公共连接 / 断开按钮、Loading、防重复与状态文案 |
| `lib/features/devices/dashboard_pairing.dart` | 配对结果展示；TLS 回退时保留提示而不立即关闭弹窗 |
| `lib/app/l10n/tables/app_l10n_device_connections.dart` | 中文 / 英文连接状态及排障提示 |

无需新增依赖、持久化密钥或 MethodChannel。子窗口沿用现有语言广播；新状态只属于主窗口连接管理。销毁编排器后取消离线宽限 Timer、跳过排队命令和后续探测；已经启动的 CLI 由 `AdbService` 原有超时回收机制负责。

### 自动验证

```bash
flutter test --no-pub test/adb_wireless_coordinator_test.dart test/wireless_connection_provider_test.dart test/device_wireless_controls_test.dart test/adb_service_test.dart test/harmony_device_serial_merge_test.dart
```

- 41 项测试通过：包含 USB 授权、重启去重、DHCP 更新、重复点击、错误成功退出码、mDNS 目标匹配、错机身份隔离、TCP 优先、TLS 旧 / 新端口恢复、配对端口隔离、销毁、主 / 子窗口、IP 解析、服务名分类与明暗主题 / 中英文 Widget 状态。
- 新增模块及直接修改的注册表、模型、IP 服务、文案和测试共 11 个分析入口执行定向 `flutter analyze --no-pub`，无问题。
- 扩展回归时，`test/harmony_tabs_and_wifi_test.dart` 的既有 `parseDisplayDimensions` 用例失败：测试输入为 `Display 0 / Width / Height`，当前解析要求 `Screen ID / Display ID` 格式。相关实现和测试与 HEAD 无差异，本次未修改。
- Dashboard 入口静态分析存在既有 `liquid_glass_background.dart` 未使用 import，本次未修改该无关代码。

### 待真机 / UI 验收（本次未启动应用、未操作手机）

1. 首次 USB 授权、插线时 Wi-Fi 关闭、DHCP 切换、短暂拔线和重启后重连。
2. TCP 拒绝连接、网络隔离、mDNS 被禁用、已配对 / 未配对、两部同型号手机并存。
3. TLS 转 TCP 时验证实际掉线时间、动态连接端口变化、失败恢复、旧 TLS 断开后是否被外部 ADB 自动重连及通知栏表现。
4. 已存在 scrcpy / 终端 / 文件传输时插线，检查 `adbd` 重启影响；多窗口不重复发送 `tcpip`。
5. 设备管理窄窗口、文字放大、多台设备的行高和状态提示可读性；iOS / HDC 入口保持原行为。

## 5. 手动 TCP/IP 连接弹窗内置指南

### 需求与入口
为避免忘记 USB 转 TCP/IP 的准备步骤，设备管理的共享“连接设备”弹窗在地址框下默认展示四步指南：USB 授权与 `adb devices` 检查、`adb tcpip 5555` 开启监听、查询手机 IP 并断开 USB 后连接、通过 `IP:端口 device` 验证。

- `lib/features/widgets/dashboard_common.dart`：原弹窗接入指南，地址标签明确为 IP 与端口，提示只填写地址；使用 `scrollable: true` 和 560 logical pixels 内容宽度，长说明可滚动，操作按钮保持可用。
- `lib/features/devices/widgets/tcpip_connection_guide.dart`：独立只读 `StatelessWidget`，四步说明默认展示，常见问题折叠收纳；命令使用 `SelectableText` 支持选择复制，颜色与文字样式来自当前 Theme。
- `lib/app/l10n/tables/app_l10n_devices_control.dart`：新增 `tcpip*` 中英文文案，由现有 `AppLocalizations` 读取。
- 未新增依赖、Provider、后台进程或 MethodChannel；原 `connectDevice(address.trim())` 调用、取消及 Enter 提交行为保持不变。指南本身不执行命令，“连接”按钮不会自动开启 TCP/IP 监听。

### 说明内容与命令边界
1. 电脑终端执行 ADB 命令，手机开启 USB debugging 并授权；同一局域网需允许设备间通信。
2. 多设备时使用 `adb -s <USB_SERIAL> tcpip 5555`，替换占位符为实际 USB 序列号。
3. 示例 IP 必须替换为手机当前地址；自定义监听端口与连接端口需一致。
4. `unauthorized`、`offline`、连接被拒绝、超时和找不到 adb 分别给出授权、重连、监听、网络和 PATH 排查方向。
5. 手机重启后通常需重新通过 USB 开启监听，切换网络后需重新检查 IP。
6. `adb disconnect IP:端口` 只断开连接；要关闭监听，在线时运行 `adb -s IP:端口 usb`，或接回 USB 后指定 USB serial 执行 `usb`。
7. Android 11+ 的二维码 / 配对码另走配对入口；配对端口与连接端口不可混用，也不能默认都是 5555。

基础流程依据：[Android Developers — 初次通过 USB 后无线连接](https://developer.android.com/tools/adb#wireless)。

### 验证与交接
- 影响面：共享 TCP/IP 连接弹窗及其中英文文案；不涉及设备合并、ADB 调度或投屏逻辑。
- 静态检查：本次 4 个 Dart 文件的定向 `flutter analyze --no-pub` 通过（No issues found）。全仓检查报告 53 项既有问题，包含 `test/apps_tab_filter_test.dart` 构造参数缺失、未定义标识符，以及其他模块的 warning / info；未改动这些无关文件。
- 待 UI 回归：中文 / 英文、明暗主题、小窗口及放大文字下内容可滚动；常见问题展开后无溢出；命令可选中复制；取消不连接，按钮和 Enter 使用输入地址连接。
- 按项目约定不启动应用，本次不执行真机 TCP/IP 切换或连接验证。
