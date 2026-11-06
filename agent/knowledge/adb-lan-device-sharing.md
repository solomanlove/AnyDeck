# AnyDeck 局域网 Android 设备共享

## 1. 需求与使用路径

分享方电脑 A 已通过 USB 或无线 ADB 连接 Android 手机；接收方电脑 B 使用 AnyDeck 输入分享码，将这台手机接入 B 的本机 ADB Server。双方电脑只需局域网可达；USB 场景下手机无需连接 Wi-Fi。

1. A 在设备管理的 Android 设备行点击共享图标，选择本机网卡地址，点击“开始共享”。
2. A 将完整分享码发送给 B。分享码是访问凭据，包含随机令牌与临时证书指纹。
3. B 在设备管理标题栏点击“连接共享设备”，粘贴分享码并连接。
4. B 的 AnyDeck、CLI 与 Android Studio 通过本机 ADB 使用共享设备，设备行标记“局域网共享设备”。
5. A 点击设备行共享图标或标题栏共享管理入口，可停止共享；B 可主动断开。

首版采用手动分享码连接，没有 mDNS 自动发现、云端中转或账号系统。每台共享设备同时允许一个接收端，分享最长 30 分钟；结束后旧分享码失效。重新开始共享会重新生成证书、令牌和监听端口。

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
| `device_share_invitation.dart` | 分享码解析、IPv4/端口/参数校验、256 bit 随机令牌 |
| `share_tls_identity.dart` | 后台 Isolate 生成内存 EC 私钥、自签名证书与 SHA-256 指纹 |
| `share_socket_reader.dart` | 控制消息限长、碎片/粘包读取、保留握手后的剩余字节 |
| `hosted_device_share.dart` | TLS 服务端、单接收者授权、30 分钟有效期、源端连接关闭 |
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
- 每条服务流都通过 `host:transport-id:<id>` 选择创建共享时的 transport。源设备断线、重新插线导致 transport 变化时，撤销原共享，不自动改绑。
- Bridge 使用 `anydeck_shared_device` 产品标记，使接收方识别共享来源。回环动态端口不被猜测为手机 TLS 无线调试；共享设备不显示手机无线准备/切换按钮。
- TLS 建立后校验随机令牌。接收方同时校验证书指纹，拒绝证书被替换的连接。证书私钥、分享码和令牌只保留在当前内存会话，不写日志或持久化。
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
5. 同机多通道合并后确认来源标签与命令选路；接收端原有设备历史缓存机制可能保留离线记录，不会自动重连过期分享。

ADB 协议链路与桩对端通过，不等于真实 Android Studio 调试、手机画质/延迟或所有 ROM 已验收。首版范围不包括 MTP、Fastboot、iOS、HarmonyOS 或多人独立操作同一手机；A/B 控制的是同一个系统与屏幕。

## 6. 参考资料

- [AOSP ADB 架构](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/internals.md)
- [ADB Transport 协议](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/protocol.md)
- [ADB 服务定义与 ABB 参数](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/docs/dev/services.md)
- [DeviceFarmer TCP-USB Bridge 参考](https://github.com/DeviceFarmer/adbkit/tree/master/src/adb/tcpusb)
- [Apple 局域网隐私说明](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
