# AnyDeck 局域网 Android 设备共享

## 1. 需求与使用路径

分享方电脑 A 已通过 USB 或无线 ADB 连接 Android 手机；接收方电脑 B 使用 AnyDeck 输入分享码，将这台手机接入 B 的本机 ADB Server。双方电脑只需局域网可达；USB 场景下手机无需连接 Wi-Fi。

1. A 在 Android 设备行点击共享，选择地址和 30 分钟（推荐）/1 小时/永久，可为当前 Wi-Fi 开启自动准备，再点击“开始共享”。
2. A 将完整分享码发送给 B。分享码是访问凭据，包含随机令牌与固定证书指纹。
3. B 在设备管理标题栏点击“连接共享设备”，粘贴分享码并连接。
4. B 的 AnyDeck、CLI 与 Android Studio 通过本机 ADB 使用共享设备，设备行标记“局域网共享设备”。
5. B 断开后设备行消失，记录保留在共享管理的“共享设备历史”中，点击重连即可再次连接已准备的共享。
6. A 可停止或删除规则；启用自动规则后，此电脑回到指定 Wi-Fi 且原手机在线时自动准备，等待 B 主动连接。

首次仍通过分享码授权，没有账号或云端中转。每台共享设备同时允许一个接收端；共享时长可配置，永久表示不自动到期，主窗口/托盘进程仍需运行。同一保存规则重新准备时复用身份和令牌，由局域网 UDP 定位新地址；删除规则后旧分享码失效。旧版本生成的临时分享码仍可用于原会话，不能跨分享方重建恢复。

## 2. 架构与职责

```text
B 的 AnyDeck / Android Studio / CLI
    → B 的本机 ADB Server :5037
    → B 的回环 Transport 入口 127.0.0.1:动态端口
    → 固定证书 SHA-256 的 TLS 连接
    → A 的单设备 ADB Bridge
    → A 的本机 ADB Smart Socket :5037
    → 创建共享时绑定的 transport ID
    → 原手机 USB / 无线 ADB 连接
```

| 模块 | 职责 |
| --- | --- |
| `lib/core/device_share/device_share_service.dart` | 会话所有者、防重复、源设备校验、主窗口销毁回收 |
| `device_share_provider.dart` | 主窗口 Provider、设备发现订阅、系统退出请求处理 |
| `device_share_models.dart` / `device_share_store.dart` | 时长、分享方规则、接收历史与私有文件原子存储 |
| `device_share_auto_prepare.dart` | 指定 Wi-Fi、原手机身份、网络进入窗口与切网/拔线回收 |
| `device_share_network_watch.dart` | 按需订阅网络事件、防抖、串行读取与低频校验 |
| `device_share_discovery.dart` | 查询已知身份的新地址，UDP 不传输访问令牌 |
| `device_share_invitation.dart` | 分享码解析、IPv4/端口/参数校验、256 bit 随机令牌 |
| `share_tls_identity.dart` | 后台 Isolate 生成内存 EC 私钥、自签名证书与 SHA-256 指纹 |
| `share_socket_reader.dart` | 控制消息限长、碎片/粘包读取、保留握手后的剩余字节 |
| `hosted_device_share.dart` | TLS 服务端、单接收者授权、可选到期时间、源端连接关闭 |
| `joined_device_share.dart` | 固定证书连接、回环入口、本机 `adb connect`、断开和撤销 |
| `adb/shared_adb_backend.dart` | Smart Socket 请求、固定 transport、Feature 协商 |
| `adb/shared_adb_peer.dart` | ADB Transport 握手、设备服务白名单、多路流管理 |
| `adb/adb_bridge_stream.dart` | 单流 ACK、二进制转发、背压与关闭 |
| `adb/shared_adb_reverse.dart` | 会话内 Reverse 映射、设备回连转发、列表过滤与规则回收 |
| `lib/features/devices/widgets/device_share_*.dart` | 共享按钮、分享码、接收入口、网络地址和会话管理 |

网络 I/O 使用 Dart 异步 Socket 与原生 TLS，复用现有 Rust 投屏和解码链路，不增加视频解码或重编码过程。新增 `basic_utils` 用于临时证书生成；`crypto` 从传递依赖提升为直接依赖，用于 SHA-256。没有新增常驻 CLI sidecar、原生插件或手机 APK。

macOS `Info.plist` 增加 `NSLocalNetworkUsageDescription`，说明局域网访问和设备共享用途；现有 Debug/Release 均未启用 App Sandbox，不扩展其他 entitlement。系统的实际授权弹窗仍需签名应用真机验收。

## 3. 协议与隔离

- 双方原有 ADB Server 不被重启或替换，不修改全局 `ADB_SERVER_SOCKET`，也不把 A 的整个 5037 端口导出。
- 源设备必须在线、已授权，且带有数值 transport ID；iOS、HarmonyOS、其他共享来源不允许创建共享。
- 每条服务流都通过 `host:transport-id:<id>` 固定当前会话的 transport。源设备断线/transport 变化先撤销旧会话；已授权的自动规则只在确认原手机身份后另建新会话，不能把原流改绑到另一台手机。
- Bridge 使用 `anydeck_shared_device` 产品标记，使接收方识别共享来源。回环动态端口不被猜测为手机 TLS 无线调试；共享设备不显示手机无线准备/切换按钮。
- TLS 建立后校验随机令牌，接收方固定证书指纹。新版本规则和历史保存于应用私有目录（0700）及文件（0600；Windows 沿用用户 AppData ACL），不写入日志、SharedPreferences 或 UDP；删除分享方规则撤销该保存身份。
- 接收方监听仅绑定 `127.0.0.1`。源端最多接纳有限数量握手连接，每台设备仅允许一个已认证接收者。
- 控制消息最大 4096 字节；ADB 单报文最大 1 MiB；最多 64 条并行 Stream、16 条 Reverse 规则。网络请求和写入有超时，慢消费者通过 ACK 与 Socket 背压限制积压。
- 只转发设备服务，禁止 `host:*`、重新选择 transport、宿主 Server 控制以及直接切换 `tcpip/usb`。完整共享仍具有设备 ADB Shell 能力，不能把它解释为只读权限。
- ABB/ABB_EXEC 的参数使用 NUL 分隔，必须保留；其他服务拒绝嵌入 NUL。只宣告支持透明转发的 Feature，未宣告 `delayed_ack`。

停止共享会先关闭监听和现有 Socket，再等待当前服务与 Reverse 清理完成；并发调用共享同一个关闭 Future。正在创建的 Reverse 请求也必须结束并撤销，避免产生迟到规则。关闭弹窗不停止已创建的共享，主窗口后台或托盘状态可继续共享。

## 4. Reverse 与投屏

`adb forward` 由 B 的本机 ADB Server 创建，所以投屏、JDWP 和网页调试的本机端口仍在 B。Bridge 转发其后续设备 Socket 请求。

`adb reverse` 的设备端监听实际属于 A 连接的手机，需要改写：

1. A 创建回环临时监听，将本次设备 Reverse 的目标指向该监听。
2. 手机回连时，A 通过 ADB Transport `A_OPEN` 请求 B 的本机目标，例如 `tcp:8081`。
3. B 的 ADB Server 将它连接到 B 的实际服务。
4. 查询只展示本会话规则；删除只操作本会话规则，新建使用 `norebind` 避免覆盖其他工具的规则。

首版 Reverse 支持 `tcp:设备端口 → tcp:接收端口`，包括动态设备端口；不导出任意宿主 Unix Socket。强杀分享方进程等无法执行退出清理的情形，设备侧 Reverse 规则仍可能需要手动检查。

现有投屏窗口、文件管理、终端、Logcat 等模块继续使用本机 ADB。子窗口不持有分享码，也不新增 MethodChannel；共享资源由主窗口持有。共享停止后投屏由原有设备断线机制处理。

## 5. 验证与验收边界

### 自动验证

```bash
flutter test --no-pub test/device_share_protocol_test.dart test/device_share_transport_test.dart test/device_share_service_test.dart test/device_share_widget_test.dart test/device_share_adb_integration_test.dart
```

- 协议：分享码校验、证书不匹配、令牌无效、单接收者、宿主命令隔离、长度/magic/checksum、碎片和粘包、来源识别、ACK 背压、撤销和创建 Reverse 的竞争。
- 会话：重复点击、源设备离线、transport 变化、禁止递归共享、停止和应用销毁。
- UI：Android 设备入口、iOS/HarmonyOS 隐藏入口、中英文、明暗主题、错误恢复、共享设备不显示无线调试切换。
- 原生 ADB 集成：使用独立端口和 `--one-device ANYDECK_SHARE_TEST_NO_USB` 的 ADB Server，关闭 mDNS 自动连接；对端是本机 Smart Socket 桩，不操作真实手机，不接管用户 ADB Server。
- 原生链路覆盖设备枚举、Shell v2 与退出码、`exec-out` 二进制、180 KB `push/pull` 内容校验、投屏 `localabstract` Forward、Reverse 回连/list/remove、ABB 流式安装数据通路及源端撤销。
- 本机验证客户端为 Android platform-tools `37.0.1`。没有 ADB 可执行文件的环境会明确跳过原生集成文件。

本轮 44 项新增测试与 107 项相关回归共 **151 项全部通过**。新增模块及直接修改的模型、连接分类、本地化与测试共 16 个定向分析入口执行 `flutter analyze --no-pub` 无问题；`git diff --check` 通过。所有新增 Dart 文件按职责拆分并控制在 500 行以内。未启动或构建桌面应用。

### 双电脑与真机待验收

1. A 通过 USB 连接手机，B 输入分享码，在 AnyDeck 与 Android Studio 中识别设备；确认 B 的其他本地设备可继续使用。
2. 真机投屏、音频、触控与键盘；安装真实 APK、查看文件和 Logcat；JDWP 断点、DevTools 与应用自己的 Reverse 服务。
3. 源端无线 ADB、A/B 不同系统组合、AP isolation、防火墙、多网卡、电脑切网、休眠恢复。
4. 停止共享、接收方主动断开、源设备拔线/重插、手机重启、30 分钟到期和应用退出。
5. 同机多通道合并后确认来源标签与命令选路；断开的共享通道不显示为离线设备，不影响同一手机的 USB/其他本地通道。

ADB 协议链路与桩对端通过，不等于真实 Android Studio 调试、手机画质/延迟或所有 ROM 已验收。首版范围不包括 MTP、Fastboot、iOS、HarmonyOS 或多人独立操作同一手机；A/B 控制的是同一个系统与屏幕。

## 6. 参考资料

- [AOSP ADB 架构](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/internals.md)
- [ADB Transport 协议](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/protocol.md)
- [ADB 服务定义与 ABB 参数](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/services.md)
- [DeviceFarmer TCP-USB Bridge 参考](https://github.com/DeviceFarmer/adbkit/tree/master/src/adb/tcpusb)
- [Apple 局域网隐私说明](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

## 7. 并发传输超时修复（2026-11-09）

### 现象与根因

PNM AN10 共享接入后显示在线，随后概览的多条 Shell 查询超时，投屏在推送 `scrcpy-server.jar` 时达到 15 秒时限。使用同一台真实手机、独立接收端 ADB Server 与 TLS 共享链路复现：单条查询成功，并发查询时部分服务停止收发，共享状态仍为在线。

多个 `AdbBridgeStream` 共用 `SharedAdbPeer` 的同一个 TLS Socket。Dart `IOSink.flush()` 尚未结束时，其他 Stream 再调用 `add/flush` 会抛出 `StateError: StreamSink is bound to a stream`。原有单流异常处理关闭服务时又可能碰到同一个写入竞争，无法正常发送 `CLSE`，使接收端持续等待直到命令超时。原来的串行服务测试没有覆盖这一场景。

### 修复逻辑

- `SharedAdbPeer._send` 使用统一的 Future 写队列，串行完成每个报文的 `add` 与 `flush`，保持跨 Stream 的报文边界与顺序。
- 单流 ACK 背压与 64 条 Stream 上限继续约束待发送数据量。
- TLS 出口写入失败或超时时关闭整个 Transport，使接收端结束失效连接。
- 共享方运行修复后的代码，停止旧共享再重新创建；接收方重新连接分享码。

### 验证与边界

- 新增 8 条服务同时返回大结果的 Transport 回归，逐流验证完整内容与关闭。修复前能复现上述 `StateError` 和 5 秒等待超时，修复后通过。
- 新增真实 ADB 并发集成：4 条设备信息查询与 900 KB 文件推送共用 Transport，所有命令、结果内容和文件字节校验通过。
- 20 个相关测试文件共 **155 项通过**；修改的生产模块与两个测试文件定向 `flutter analyze --no-pub` 无问题；`git diff --check` 通过。
- 真机为 PNM AN10，分享方与隔离接收端 ADB 在同一台 Mac 上运行。修复后，4 路查询（含约 1.8 MB 输出）及 732,226 字节投屏 Server 推送成功；进一步保持 H.264 视频数据链路 20 秒，同时执行 24 次查询及 6 次文件推送，接收端持续在线。
- 测试仅使用独立临时文件、Forward 和后台 scrcpy Server，结束后回收测试进程、连接与临时文件；未启动或构建桌面项目。跨两台电脑的 Wi-Fi、音频、触控与长时共享仍按前述真机清单验收。

## 8. 概览加载缓慢与信息再次消失修复（2026-11-09）

### 现象与定位

共享设备能显示型号、Android 版本，但电池、Android ID、内存、存储、网络与屏幕参数加载慢，曾显示的信息随后又消失。最新主窗口日志仍有分组 Shell、`dumpsys wifi/display` 和 Root 探针达到 15 秒时限的记录。定位到两个独立缺陷：

1. `SharedAdbPeer.run` 在收到 `OPEN` 时等待后端 Smart Socket 完成连接。在某个服务建立缓慢时，整个 Transport 的消息读取暂停，其他 Stream 的 ACK、关闭以及后续 OPEN 均无法处理。此前的统一写队列只解决出口并发写入，未覆盖入口阻塞。
2. `DeviceInfoService.loadOverview` 只校验 `getprop` 的退出码。其他命令超时后返回空输出，仍被解析为未知字段，并保存成新的概览覆盖原缓存，造成信息再次消失。

通过可控 Socket 桩在服务回复 `OKAY` 前挂起握手，以及模拟单组 Shell/dumpsys 超时，修复前的 8 条核心用例均失败，分别复现其他流无法继续和完整缓存被残缺结果覆盖。

### 修改边界

- `SharedAdbPeer` 异步建立不同设备服务，读取循环继续处理其他流；所有出口仍经原有 FIFO 写队列，并保留单流 ACK 背压。
- 建立中的 OPEN 和已建立 Stream 合计最多 64 条，同时拒绝复用建立中的远端 ID；停止共享等待迟到连接完成并销毁，Reverse 回连也遵守同一容量限制。
- `DeviceInfoService` 校验属性、硬件分组、设置分组和两条 dumpsys 结果。查询失败时使用现有缓存，不写入残缺结果，也不刷新原采集时间；没有缓存或调用方禁用回退时，明确报告失败。
- 序列号仍可从属性回退；旧系统不支持分组脚本最后的可选命令，但已输出末尾分组标记时，继续使用此前采集的数据，避免破坏旧 Android 兼容性。
- 未增加自动重试或后台轮询；没有修改 UI、文案、主题、投屏解码或手机无线调试状态。

### 自动验证与真机边界

```bash
flutter test --no-pub test/device_share_protocol_test.dart test/device_share_transport_test.dart test/device_share_pending_open_test.dart test/device_share_service_test.dart test/device_share_widget_test.dart test/device_share_adb_integration_test.dart test/device_overview_test.dart test/device_overview_refresh_failure_test.dart test/device_root_status_provider_test.dart test/overview_identity_test.dart test/overview_foldable_display_test.dart test/overview_layout_test.dart test/mcp_device_tools_test.dart
```

- 13 个相关测试文件共 **107 项通过**；修改的 6 个 Dart 源码/测试入口定向分析无问题，`git diff --check` 通过。
- 新增覆盖慢 OPEN 与其他流 ACK/查询互不阻塞、64 条建立中服务上限、重复 ID 拒绝、停止时迟到连接回收；原生隔离 ADB 也验证慢服务尚未建立时其他查询能完成。
- 概览回归逐组验证硬件、设置、Wi-Fi、显示查询超时不覆盖字段和采集时间；覆盖首次失败不保存、禁用回退时显式失败以及旧系统末尾可选命令兼容。
- 当前在线真机为 Mi MIX 3，截图中的 PNM AN10 不在线。使用同机 USB 分享方、TLS 链路和独立接收端 ADB，直接调用生产 `DeviceInfoService.loadOverview`，禁用缓存回退，并行读取 Shell 身份，5 轮完整概览均成功，耗时 **793–871 ms**；直接 USB 基线为 822 ms。
- Android ID、内核、内存总量、网络和屏幕等稳定字段与 USB 结果一致，电池、内存占用与存储均有结果。CPU 可用核数由 `nproc` 提供，实测会在 6 与 8 之间变化，按动态采样处理，不把它误判为共享字段丢失。
- 真机检查只读设备信息，SharedPreferences 使用测试内存缓存；接收端 ADB 使用独立端口且禁止发现 USB，结束后已关闭共享和测试 Server，未重启用户默认 ADB Server，未启动或构建桌面项目。

两端运行本次修改后的版本，分享方停止旧共享并重新生成分享码，接收方重新连接。人工回归重点是概览显示完整后反复刷新、查询超时但设备仍在线时保留原信息，以及并发投屏/文件传输时继续读取概览。PNM AN10、桌面实际页面、跨两台电脑 Wi-Fi 与长时稳定性仍需实际环境验收；同机多轮只读查询通过不代表这些场景均已通过。

## 9. 历史重连、共享期限与指定 Wi-Fi 自动准备（2026-11-09）

### 使用与状态语义

| 操作 | 行为 |
| --- | --- |
| 接收端首次输入分享码 | 成功后保存名称、固定身份、最新地址、访问凭据和上次连接时间 |
| 接收端断开 | 关闭本机回环 ADB 连接，设备管理不保留该共享的离线项；共享管理保留重连历史 |
| 历史重连 | 局域网查找原身份的新地址，再按原 TLS 指纹/令牌认证；不会自动连接未知设备 |
| 30 分钟 / 1 小时 | 从本次准备开始计时，到期关闭监听和已连接 Transport |
| 永久 | 不创建到期 Timer；手动停止、源设备离线、退出应用仍会关闭会话 |
| 自动准备 | 用户明确为当前 Wi-Fi 开启后，主窗口/托盘运行且原手机在线时等待接收者连接 |
| 手动停止 / 暂停自动共享 | 同时持久暂停该自动规则，状态刷新和重新入网不会立即重开 |
| 删除我的共享规则 | 关闭会话并移除保存身份；以后重新创建会生成新身份，旧分享码不可用 |
| 删除接收历史 | 断开该连接并删除本机重连凭据，不修改分享方的规则 |

主窗口启动即恢复规则，不依赖打开设备管理或共享弹窗；子窗口不读取凭据文件，也不持有自动准备任务。接收端重连仍是用户主动操作，自动规则只负责让分享方处于就绪状态。

### 连接定位与私有存储

- 保存规则复用设备专属 TLS 身份与 token，接收历史以证书指纹去重，最多保存最近 50 条。持久身份的证书用于跨会话认证；业务期限由独立 Timer 控制，不以证书有效期代替 30 分钟/1 小时授权窗口。
- 私有文件为应用支持目录下 `device-sharing/state.json`。只在主窗口写入，通过 Future 队列串行保存，先限制目录/临时文件权限，再写入并原子替换；文件损坏时明确报错，不把读取失败当作空历史覆盖。
- `anydeck-share` v1 分享码增加可选 `resume=1` 和 `exp` 字段，保持旧码解析兼容。连接成功后的期限来自已通过 TLS 认证的分享方回复。
- 地址定位使用 UDP 52847，向已知地址、IPv4 广播和 `239.255.88.21` multicast 查询已知证书指纹；请求带随机 nonce，单次最长 1.2 秒、最多一次重发，回复限长与限速。不进行设备列表枚举，不发送 token、私钥或完整分享码。
- UDP 发现失败时尝试历史地址；分享方未准备、已到期或身份已被删除时明确提示重连失败。网络屏蔽 UDP 且地址/端口已变化时，可重新粘贴当前分享码。

### Wi-Fi 与并发边界

- macOS 通过 `NWPathMonitor` 和 CoreWLAN SSID 变更事件触发读取，150 ms 合并事件；5 秒低频校验覆盖系统事件缺失。仅存在已启用自动规则时订阅，全部暂停/删除后取消 Timer、原生网络和 Wi-Fi 监听。
- 自动读取使用 `readForSharing`，只信任系统当前关联的 `verifiedWifiSsid`，不触发 Swift CLI、Wi-Fi 扫描或用邻近网络猜测名称。现有底栏展示回退继续独立工作。其他平台缺少可信当前 SSID 时不启用自动规则，历史重连和手动期限不依赖该能力。
- 自动规则匹配分享方电脑的 Wi-Fi，不是要求手机切换 Wi-Fi。共享监听绑定选定的本机 IPv4；离开指定网络时关闭自动会话。手机仍需作为在线 ADB 设备连接到分享方。
- 每次进入指定 Wi-Fi 维护一个授权窗口。USB 重插、transport 变化和同一 Wi-Fi 的 IP 更新可在原窗口内重新准备，不自动续期；窗口到期后等待用户重新开始或下一次重新进入网络。应用重启重新评估规则并开始新的准备窗口。
- 网络/设备变化与握手并发时，迟到会话会再次检查当前网络、设备 transport 和规则启用状态并回收。用户在自动握手中点击停止会排队执行，不因短暂 busy 丢弃。

### 验证与手动验收

```bash
flutter test --no-pub test/device_share_*.dart
```

- 本轮共享、概览、设备注册表、无线连接、子网提示、设备菜单、主窗口导航与快捷键等 29 个文件共 **211 项通过**；20 个定向分析入口无诊断，网络桥接文件独立 `swiftc -typecheck` 通过，`git diff --check` 通过。
- 新增回归覆盖私有存储权限和原子保存、历史恢复/去重/删除、UDP 身份/nonce 校验、三种期限与真实到期关闭、指定 Wi-Fi 准备/离开/重返、到期不自动续期、手动停止优先、迟到连接回收、原手机身份、断开隐藏但保留本地 USB，以及中英文和明暗界面。
- 真实隔离 ADB 集成验证接收端断开后同会话重连、两端会话重建后历史恢复、新端口重连和 Shell 可用；ADB Server 使用独立端口，不接管用户默认 Server。
- 当前真机型号为 M2012K11AC，通过同机 USB 源端、TLS、UDP 与独立接收端 ADB，使用临时私有目录实际保存并恢复双方服务。两端服务重建后，历史重连并读取完整概览成功，约 **676 ms**；断开后隔离 ADB 不再枚举该设备，删除历史后文件中记录为空。临时凭据目录、Socket 和测试 ADB 均已回收，只读手机信息，未修改手机网络或安装应用。
- 未启动或构建桌面应用，也未切换用户当前 Wi-Fi；真实双电脑、系统定位授权、Wi-Fi 切换/休眠恢复与长时运行仍需人工验收。

人工重点：分享方选择期限与自动规则，接收方首次连接后断开，确认设备列表移除且历史可重连；重启双方应用或改变分享方地址后重连；离开/返回指定 Wi-Fi、手机拔插及期限到期；手动暂停后确认不自动重开，删除规则后确认旧历史认证失败。永久模式应在托盘运行期间保持等待，退出应用后会话应结束。

## 10. 投屏拥塞恢复被窗口取消（2026-11-16）

### 现象与定位

接收方的三星 SM-F9710 经局域网共享后保持 ADB 在线，投屏多次成功生成 1920×1448 解码帧，但随后结束并清理 server/forward；其中两次在首帧后约 2.7 秒停止。投屏使用 16 Mbps，旧日志只保留清理命令，未记录触发恢复的健康快照，因此不能追溯每次停止的具体触发项。

真实 `MirrorWindowApp` 的回归测试确认以下生命周期冲突：

1. 共享回环 Transport 按 TCP 投屏通道处理。连续三次每秒采样发现视频积压至少 350 ms 时，`MirrorRecoveryPolicy` 请求降档重建。
2. `ActiveEmbeddedMirrorNotifier` 停止旧会话时清空 Texture。子窗口 `deviceOnlineProvider` 以活跃投屏 Session 判断在线，随之返回 false。
3. 窗口原有在线监听再次调用 `forceStopMirroring()`，增加 generation 并重置降档策略。等待旧资源释放的自动恢复请求因 generation 变化被取消。
4. 用户手动重连仍按原画质启动，遇到持续积压后可再次触发相同冲突。旧测试的立即返回 stop 会合并空状态与新 Texture，必须用受控异步释放才能复现。

### 修复与资源归属

- Android 窗口不再根据投屏 Session 的空状态反向停止会话；实际 ADB 设备变化由 `AndroidMirrorTransportHost` 处理，异常 server 退出由投屏 Notifier 处理。iOS/HarmonyOS 保留原在线监听。
- 降档继续复用原有旧资源清理、generation 校验和 20 秒冷却。用户主动停止或恢复期间关窗仍取消迟到的启动；未增加自动共享重连或修改全局画质设置。
- `embedded_scrcpy_recovery.dart` 将 `stream_recovery_requested` 和 `stream_recovery_failed` 写入 `AppLogRecorder`，记录现有 Texture、视频积压、音频状态及目标画质，不写入设备标识或分享凭据。后续可从本地日志区分主动降档与共享设备断线。

### 验证与边界

- 新增真实窗口组件测试，覆盖共享手机降档后重建、恢复日志、正常关窗释放，以及清理期间关窗后不再启动。旧版在受控异步清理下只启动一次，修复后成功启动第二次并使用 1280/4 Mbps。
- 窗口恢复、健康策略、Android 换线、连接解析、设备事件、错误状态、剪贴板、画面几何、窗口尺寸、画质设置、iOS/HarmonyOS 回归及共享 Transport/慢 OPEN/到期关闭等 16 个文件共 **100 项通过**；4 个生产入口及新增测试定向 `flutter analyze --no-pub` 无问题，`git diff --check` 通过。
- 本机三星通过另一台 AnyDeck 的真实共享通道，使用当前 App 同一 Rust dylib、独立 scid/forward 做 CLI 解码：26 秒收到 113 帧，1920×1448、16 Mbps，期间原生会话持续运行；另一次 31 秒同时读取 `getprop`、约 3 MB 的 `dumpsys wifi` 和 `dumpsys display`，三条查询均成功且视频会话未退出。第二轮画面基本静止，只收到 22 帧，不能作为动态画面长时稳定性验收。
- 临时 server jar、scid、forward 和原生会话均已清理。未启动、重启或构建桌面应用；上述真机测试验证底层共享和解码，窗口修复由自动化测试验证。更新后的真实窗口动态画面、触控、音频与长时 Wi-Fi 波动仍需人工验收。

## 11. Android Studio 大包安装超时与共享流阻塞（2026-11-16）

### 现场证据

- Android Studio 的 “Launching on devices” 包含部署安装阶段。现场日志在 16:50:22 成功创建 PackageManager Session，随后通过 `abb` 流式传输 272,527,484 字节（约 260 MiB）APK；16:55:22 正好 5 分钟后放弃 Session 并报 `SHELL_UNRESPONSIVE`。未进入 Activity 启动或 JDWP attach，不能把该现象归为 App 启动失败。
- 同时运行的另一个 IDE 在安装期间读取共享设备属性超时。此前 12 KB 的 `abb_exec` 安装桩测试不能代表大包 `abb` / Shell v2 的完整路径。
- 真实共享三星的 4 MiB 无压缩上传耗时 8.354 秒（0.479 MiB/s），回读耗时 6.253 秒且 SHA-256 一致。另以独立临时安装 Session 验证 `abb` 输入流：8 MiB 用时 23.911 秒后返回响应，随后弃置 Session，没有 commit、安装或启动用户 App。按该吞吐传输完整 APK 会超过 IDE 的 5 分钟时限。
- 分享方地址的 4 次 ICMP 往返为 7.961～234.196 ms，平均 105.214 ms；该短测只说明现场延迟波动，不能据此判断具体路由器、频段或源端 USB 的故障。

### 入站写入与流隔离

- 原 `SharedAdbPeer.run()` 在收到 `WRTE` 后等待单条后端服务 `flush()`，最长 15 秒；此时同一 Transport 上其他流的 ACK、关闭和 OPEN 均不能处理。用可控 `flush` gate 确认：仅一条服务停止消费输入，即可让另一条 8192 字节视频流在首块确认后停止发送第二块。
- `AdbBridgeStream` 现在独立处理写入，Transport 循环继续分派其他流事件。Legacy ADB 每流最多接纳一块未确认输入，违规重复写入只关闭该服务，不建立无界 Future 队列。
- 本流输入额度持续占用到 `OKAY` 真正进入 TLS 写入前，再由统一 FIFO 的 `beforeWrite` 释放；既避免 ACK 排队期间输入无界积压，也避免已收到 ACK 的快速回包被误拒绝。对端关闭会销毁后端 Socket，清理未完成写入。

### 大包流控依据

[AOSP Transport 协议](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/protocol.md) 允许接收 `WRTE` 后立即发送 `READY`，也允许本地服务写入后才确认；服务层字节可以在不改变顺序的前提下重新分包。小块数据逐次等待跨局域网 ACK 时，吞吐受包大小与往返延迟限制。

`delayed_ack` 需要双方协商，当前共享未宣告该能力；AOSP Host 还通过 `ADB_BURST_MODE` 控制它。不能为单设备共享重启用户的全局 ADB Server 或静默修改其环境，参见 [AOSP Delayed ACK](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/delayed_ack.md)。

### 接收端有界上传聚合

- `adb/shared_adb_bulk_relay.dart` 接管最多四条由本机发起的 `sync:`、`abb:`、`abb_exec:` 上传流。向本机 ADB 提前发布有界 `OKAY`，把等待远端 ACK 期间积压的服务字节合并为不超过协商 maxPayload 的一个 `WRTE`；对分享方仍严格每流只发送一块未确认数据，兼容原 Legacy ADB Bridge。
- 每流窗口随协商 payload 大小变化，最多 1 MiB；计入在途和缓存字节，窗口满后暂停本地 ACK，最多再保留一块已在途的本机输入。没有整包缓存或无界 Future 队列。ACK 真正进入 Socket 前才释放下一块本机输入额度，零字节包不加入数据队列。
- 远端数据 ACK 被代理消费，不能再次传给已获提前确认的本机 ADB；初始 OPEN 的 ACK 独立处理。Stream ID pair 校验、失败 OPEN 和远端关闭负责释放对应状态；远端先关闭时取消尚未写出的缓存与提前 ACK。
- 本机 CLSE 等待已接纳的字节按序排空后才送往分享方。普通 Shell、视频流、第五条批量流以及源端发起的 Reverse 维持透明转发；本改动不承诺 pull 提速。两个 Socket 出口各自用 FIFO 串行写入。
- `JoinedDeviceShare` 在完成原有证书指纹和 token 认证后使用聚合 Relay。终止时通过可注入诊断回调记录 `relay_input_closed direction=local|remote error_type=...`，由主窗口落入 `device_share` 本地日志；不记录原始异常文本、设备 ID、分享码或 payload。主动停止先取消 Relay，不误报为网络异常。

### 验证边界与使用要求

- 原生隔离 ADB 集成新增与现场相同大小的 **272,527,484 字节** `abb` / Shell v2 输入，逐 64 KiB 发送、解析与 SHA-256 校验，验证 NUL 参数、stdin/EOF、完整响应和退出码，以及安装输入未完成时独立 Shell 查询仍成功。不连接真实手机，也不生成、安装或启动 App。
- 慢写入测试覆盖独立流 ACK、关闭回收、重复 WRTE 有界、ACK 排队与快速回包；聚合测试覆盖窗口背压、减少远端确认次数后的内容 hash、延迟 CLSE、远端关闭取消、错误 ID、四流上限及非批量/Reverse 透传。
- 共享、概览和投屏恢复等 **19 个文件共 134 项测试通过**，包含完整 260 MiB ABB 数据回归；10 个修改/新增 Dart 入口定向 analyze 无诊断，新增文件格式和 `git diff --check` 通过。
- 17:13:16 真实共享连接再次整体关闭，当时进行的额外传输验证失败；缺少旧版本终止方向日志，不能确认这次关闭的原因。随后用保存的身份和独立接收端 ADB 重新连接，回读型号确认仍是同一台三星：更新后 8 MiB 上传耗时 8.959 秒，SHA-256 一致、4 次并发查询全部成功，会话持续在线。
- 真实手机的更新后 `abb` 8 MiB 输入耗时 11.547 秒，返回 `Success`，临时安装 Session 已成功弃置；先前样本为 23.911 秒。两轮采样时间不同，不能把差异全部归因于代码；尚未验证 260 MiB 用户 APK 在真实 IDE 中完整安装、启动和 Debug attach，也不承诺长时 Wi-Fi 稳定性。临时远端数据、Session、Socket 和隔离 ADB Server 已清理。
- 更新接收方后可使用上传聚合与终止方向日志；分享方也需更新并重建共享，才能应用后端慢写流隔离。重连后 Android Studio 应选中当前在线的共享设备，再验证同一 APK 的完整安装、启动与 Debug attach。未主动启动或重启桌面 App、IDE、用户 ADB Server 或用户手机 App。
