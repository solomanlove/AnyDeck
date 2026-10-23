# Android 视频 DLNA 投到 macOS

## 目标与入口

- macOS 主窗口顶部的 DLNA 图标启停接收服务；Android 视频 App 与电脑处于同一局域网时，选择 `AnyDeck DLNA`。
- 只接收视频媒体地址与播放控制，不采集 Android 手机屏幕，也不影响现有 scrcpy / AirPlay 会话。
- 当前基于 AVPlayer 的播放格式范围是 MP4 与 HLS；视频源的鉴权、独立音视频 DASH 流、DRM 与弹幕不在本次通用 DLNA 接收能力内。

## 数据与控制链路

1. `lib/core/dlna/dlna_renderer_service.dart` 绑定 SSDP UDP `1900`，发布 `MediaRenderer:1`，并在收到 `M-SEARCH` 后回复设备描述地址。
2. 同一服务在固定 TCP `18583` 端口提供设备描述、`AVTransport`、`RenderingControl`、`ConnectionManager` 的 SCPD 与 SOAP 接口，避免手机缓存重启前的随机端口。
3. Android 控制端下发 `SetAVTransportURI` / `Play` / `Pause` / `Stop` / `Seek`。媒体 URL 不经 Flutter 转发，由 macOS `AVPlayer` 直接获取。
4. `macos/Runner/DlnaPlayerBridgeService.swift` 通过 `any_deck/dlna_player` MethodChannel 接收播放命令，使用 `AVPlayerLayer` 在独立 macOS 窗口显示。
5. 关闭播放窗口会停止播放器并通知 Dart；关闭 DLNA 接收开关会发送 SSDP `byebye`、释放 UDP/TCP 端口、清空订阅及播放器。

## 协议与系统边界

- SSDP 使用 multicast `239.255.255.250:1900`，需要手机和电脑之间允许局域网发现与访问；不同 VLAN、访客 Wi-Fi、AP isolation 或 macOS 防火墙均可能阻断发现。
- 设备描述和 SOAP 使用 HTTP；`Info.plist` 中的 `NSAllowsArbitraryLoadsForMedia` 仅为 AVFoundation 媒体请求放开 ATS，普通网络请求不随之放开。该配置在 App Store 审核时需要说明用途。
- 服务没有增加 ADB 命令、后台进程或跨 Isolate 同步；主窗口作为唯一 DLNA 服务 owner。
- 通用 DLNA 能否被 B 站特定版本识别，以及 B 站下发的 URL 能否由 AVPlayer 播放，必须以真实 Android 手机与真实视频验证。成功编译和协议单测不能证明该点。

## 黑屏排查记录

- 真机复现显示设备可发现、原生窗口黑屏。主窗口日志发现 `GetPositionInfo` 在原生通道返回整数零时抛出 `int` 到 `double` 的类型转换错误；现已按 `num` 接收后转为 `double`。
- 本地 H.264/AAC MP4 用支持 HTTP Range 的服务器测试时，原生窗口可播放且进度递增；不支持 Range 的简单 HTTP 服务器触发 `Operation Stopped`，因此接收端不能只凭 `PlayResponse` 判定视频播放成功。
- 重启进程可能让手机继续使用旧的随机 HTTP 端口。现将设备名称改为 `AnyDeck DLNA`、变更 UDN，并固定 HTTP 端口 `18583`。保留 SOAP 动作和 AVPlayer 错误日志，供真机复测定位媒体源问题；日志不记录完整媒体 URL 或签名查询参数。
- 新版在电脑上已监听 UDP `1900` 和 TCP `18583`，设备描述返回 `AnyDeck DLNA`。最初复测没有收到播放命令，原因是换用 `192.168.31.54` 的手机后，B 站投屏页仍显示旧会话；从该手机返回视频页并重新发起投屏后，接收端收到 `SetAVTransportURI` / `Play`，原生窗口出现实际 B 站视频画面。`GetPositionInfo` 两次读取分别为 `00:00:25` 与 `00:00:30`，时长 `00:27:43`，确认播放进度持续增长。

## 已执行验证

- `flutter analyze --no-pub lib/core/dlna lib/features/dlna`：通过。
- `flutter test --no-pub test/core/dlna/dlna_protocol_test.dart test/core/dlna/dlna_player_bridge_test.dart`：6 项通过。
- `flutter build macos --debug --no-pub`：通过；已启动 Debug App 并验证 SSDP / HTTP 监听、设备描述及 B 站真机视频播放。声音、暂停、跳转与停止尚未逐项验收。

## 真机验收清单

1. 同一 Wi-Fi 下点击 DLNA 图标，在 Android B 站视频页点 `TV`，确认列表可见 `AnyDeck DLNA`。
2. 选择接收端，确认视频和声音实际播放；分别验证 MP4 与 HLS 来源，以及暂停、继续、进度跳转、音量和停止。
3. 手机切换 Wi-Fi、电脑睡眠/唤醒、断开网络后重新启用，确认服务可重新被发现，无遗留端口占用。
4. 关闭播放器窗口与关闭 DLNA 开关，确认手机端状态更新、电脑停止播放。
5. 验证 macOS Light/Dark 下图标状态与中英文文案；确认 Android scrcpy 与 iOS AirPlay 原有操作不受影响。
