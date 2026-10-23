# Android 视频 DLNA 投到 macOS

## 目标与入口

- macOS 主窗口顶部的 DLNA 图标启停接收服务；Android 视频 App 与电脑处于同一局域网时，选择 `AdbManage DLNA`。
- 只接收视频媒体地址与播放控制，不采集 Android 手机屏幕，也不影响现有 scrcpy / AirPlay 会话。
- 当前基于 AVPlayer 的播放格式范围是 MP4 与 HLS；视频源的鉴权、独立音视频 DASH 流、DRM 与弹幕不在本次通用 DLNA 接收能力内。

## 数据与控制链路

1. `lib/core/dlna/dlna_renderer_service.dart` 绑定 SSDP UDP `1900`，发布 `MediaRenderer:1`，并在收到 `M-SEARCH` 后回复设备描述地址。
2. 同一服务在随机 TCP 端口提供设备描述、`AVTransport`、`RenderingControl`、`ConnectionManager` 的 SCPD 与 SOAP 接口。
3. Android 控制端下发 `SetAVTransportURI` / `Play` / `Pause` / `Stop` / `Seek`。媒体 URL 不经 Flutter 转发，由 macOS `AVPlayer` 直接获取。
4. `macos/Runner/DlnaPlayerBridgeService.swift` 通过 `any_deck/dlna_player` MethodChannel 接收播放命令，使用 `AVPlayerLayer` 在独立 macOS 窗口显示。
5. 关闭播放窗口会停止播放器并通知 Dart；关闭 DLNA 接收开关会发送 SSDP `byebye`、释放 UDP/TCP 端口、清空订阅及播放器。

## 协议与系统边界

- SSDP 使用 multicast `239.255.255.250:1900`，需要手机和电脑之间允许局域网发现与访问；不同 VLAN、访客 Wi-Fi、AP isolation 或 macOS 防火墙均可能阻断发现。
- 设备描述和 SOAP 使用 HTTP；`Info.plist` 中的 `NSAllowsArbitraryLoadsForMedia` 仅为 AVFoundation 媒体请求放开 ATS，普通网络请求不随之放开。该配置在 App Store 审核时需要说明用途。
- 服务没有增加 ADB 命令、后台进程或跨 Isolate 同步；主窗口作为唯一 DLNA 服务 owner。
- 通用 DLNA 能否被 B 站特定版本识别，以及 B 站下发的 URL 能否由 AVPlayer 播放，必须以真实 Android 手机与真实视频验证。成功编译和协议单测不能证明该点。

## 已执行验证

- `flutter analyze --no-pub lib/core/dlna lib/features/dlna`：通过。
- `flutter test --no-pub test/core/dlna/dlna_protocol_test.dart`：4 项通过。
- `flutter build macos --debug --no-pub`：通过；未启动 App。

## 真机验收清单

1. 同一 Wi-Fi 下点击 DLNA 图标，在 Android B 站视频页点 `TV`，确认列表可见 `AdbManage DLNA`。
2. 选择接收端，确认视频和声音实际播放；分别验证 MP4 与 HLS 来源，以及暂停、继续、进度跳转、音量和停止。
3. 手机切换 Wi-Fi、电脑睡眠/唤醒、断开网络后重新启用，确认服务可重新被发现，无遗留端口占用。
4. 关闭播放器窗口与关闭 DLNA 开关，确认手机端状态更新、电脑停止播放。
5. 验证 macOS Light/Dark 下图标状态与中英文文案；确认 Android scrcpy 与 iOS AirPlay 原有操作不受影响。
