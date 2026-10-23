# Android 视频 DLNA 投到 macOS

## 目标与入口

- macOS 主窗口顶部的 DLNA 图标启停接收服务；Android 视频 App 与电脑处于同一局域网时，选择 `AnyDeck DLNA`。
- “设置 → 投屏设置 → Android DLNA 投屏名称”可以修改手机设备列表中的接收端名称；空白名称恢复为 `AnyDeck DLNA`。
- 只接收视频媒体地址与播放控制，不采集 Android 手机屏幕，也不影响现有 scrcpy / AirPlay 会话。
- 当前基于 AVPlayer 的播放格式范围是 MP4 与 HLS；视频源的鉴权、独立音视频 DASH 流、DRM 与弹幕不在本次通用 DLNA 接收能力内。

## 数据与控制链路

1. `lib/core/dlna/dlna_renderer_service.dart` 绑定 SSDP UDP `1900`，发布 `MediaRenderer:1`，并在收到 `M-SEARCH` 后回复设备描述地址。
2. 同一服务在固定 TCP `18583` 端口提供设备描述、`AVTransport`、`RenderingControl`、`ConnectionManager` 的 SCPD 与 SOAP 接口，避免手机缓存重启前的随机端口。
3. Android 控制端下发 `SetAVTransportURI` / `Play` / `Pause` / `Stop` / `Seek`。媒体 URL 不经 Flutter 转发，由 macOS `AVPlayer` 直接获取。
4. `macos/Runner/DlnaPlayerBridgeService.swift` 通过 `any_deck/dlna_player` MethodChannel 接收播放命令，使用 `AVPlayerLayer` 在独立 macOS 窗口显示；视频保持原比例时，窗口与播放层以黑色填充留白。
5. 关闭播放窗口会停止播放器并通知 Dart；关闭 DLNA 接收开关会发送 SSDP `byebye`、释放 UDP/TCP 端口、清空订阅及播放器。
- `RenderingControl` 的音量与静音由原生播放器分别保存；取消静音不会把先前音量重置为 100%，换片源后仍使用当前音量与静音状态。

## 名称设置与热更新

- `AppSettings.dlnaServerName` 默认 `AnyDeck DLNA`，使用 SharedPreferences 键 `settings.dlnaServerName` 持久化，并沿用设置广播同步到其他窗口。设置页与 iOS AirPlay 名称共用接收端名称编辑组件。
- 主窗口的 `DlnaRendererService.setServerName` 更新设备描述中的 `<friendlyName>`；XML 文本经转义，`UDN` 与 TCP `18583` 保持稳定。服务运行时发送 SSDP `byebye` 再发送 `alive`，不调用 `stop()`，因此不主动关闭正在播放的视频。
- 工具栏启用服务前读取当前设置，启动提示使用实际名称；macOS 原生播放器标题也通过 `setTitle` MethodChannel 更新。手机端可能缓存设备描述，需要重新搜索设备列表才能看到新名称。

## 协议与系统边界

- SSDP 使用 multicast `239.255.255.250:1900`，需要手机和电脑之间允许局域网发现与访问；不同 VLAN、访客 Wi-Fi、AP isolation 或 macOS 防火墙均可能阻断发现。
- 设备描述和 SOAP 使用 HTTP；`Info.plist` 中的 `NSAllowsArbitraryLoadsForMedia` 仅为 AVFoundation 媒体请求放开 ATS，普通网络请求不随之放开。该配置在 App Store 审核时需要说明用途。
- 服务没有增加 ADB 命令或后台进程；主窗口作为唯一 DLNA 服务 owner，名称设置沿用现有跨 Isolate 广播。
- 通用 DLNA 能否被 B 站特定版本识别，以及 B 站下发的 URL 能否由 AVPlayer 播放，必须以真实 Android 手机与真实视频验证。成功编译和协议单测不能证明该点。

## 黑屏排查记录

- 真机复现显示设备可发现、原生窗口黑屏。主窗口日志发现 `GetPositionInfo` 在原生通道返回整数零时抛出 `int` 到 `double` 的类型转换错误；现已按 `num` 接收后转为 `double`。
- 本地 H.264/AAC MP4 用支持 HTTP Range 的服务器测试时，原生窗口可播放且进度递增；不支持 Range 的简单 HTTP 服务器触发 `Operation Stopped`，因此接收端不能只凭 `PlayResponse` 判定视频播放成功。
- 重启进程可能让手机继续使用旧的随机 HTTP 端口。现将设备名称改为 `AnyDeck DLNA`、变更 UDN，并固定 HTTP 端口 `18583`。保留 SOAP 动作和 AVPlayer 错误日志，供真机复测定位媒体源问题；日志不记录完整媒体 URL 或签名查询参数。
- 新版在电脑上已监听 UDP `1900` 和 TCP `18583`，设备描述返回 `AnyDeck DLNA`。最初复测没有收到播放命令，原因是换用 `192.168.31.54` 的手机后，B 站投屏页仍显示旧会话；从该手机返回视频页并重新发起投屏后，接收端收到 `SetAVTransportURI` / `Play`，原生窗口出现实际 B 站视频画面。`GetPositionInfo` 两次读取分别为 `00:00:25` 与 `00:00:30`，时长 `00:27:43`，确认播放进度持续增长。
- 后续复测时手机投屏页虽勾选 `AnyDeck DLNA`，进度却停在 `00:00/00:00`；电脑端仍监听 UDP `1900`、TCP `18583`，设备描述正常，SOAP `GetTransportInfo` 返回 `NO_MEDIA_PRESENT`，`GetPositionInfo` 返回时长与进度 `00:00:00`。此时没有可播放媒体，因此播放器窗口不会出现；仍需通过实时请求日志区分手机未发 `SetAVTransportURI` 与请求被拒绝等情况。

## B 站手机端能力边界

- `192.168.31.54` 的 B 站投屏页在选择 `AnyDeck DLNA` 后，弹幕开关标注“官投专享”；倍速菜单中除 `1.0X` 外的选项也标注“官方投屏专享”；清晰度菜单中的 `1080P` 标注同样限制，`720P` 与 `360P` 可选。这是本次手机界面观察结果，不能把这些官方投屏功能算作通用 DLNA 已支持。
- 上述页面重启电脑 App 后仍显示旧会话且进度为 `00:00`，不代表接收端已在播放。需要返回视频页重新选择设备，并以电脑端实际窗口、声音和进度作为验收依据。
- 用户确认按“通用 DLNA 不显示弹幕并在产品中明确说明”验收；设置页 DLNA 名称说明和启动提示均使用与视频 App 无关的文案，不把弹幕列为可用能力。

## 已执行验证

- `flutter analyze --no-pub lib/core/dlna lib/features/dlna`：通过。
- `flutter test --no-pub test/core/dlna/dlna_protocol_test.dart test/core/dlna/dlna_player_bridge_test.dart`：6 项通过。
- `flutter build macos --debug --no-pub`：通过；已启动 Debug App 并验证 SSDP / HTTP 监听、设备描述及 B 站真机视频播放。声音、暂停、跳转与停止尚未逐项验收。
- 名称与控制增量：定向 `flutter analyze --no-pub` 通过；设置、名称编辑 Widget、协议、原生通道和 SOAP 控制共 13 项 `flutter test --no-pub` 通过；`flutter build macos --debug --no-pub` 通过。SOAP 集成测试覆盖运行时改名、设备描述、播放、暂停、继续、跳转、停止、音量与静音。该测试使用原生播放器 MethodChannel mock，不等同于听到真实声音或看到真机控制后的播放窗口变化。
- 运行中的 AnyDeck 已占用固定端口 `18583`，再次并行执行 SOAP 集成测试会因端口占用失败；这是测试环境冲突，不是断言失败。其余 10 项定向测试、定向分析、`git diff --check` 和包含黑色留白改动的 macOS Debug 构建通过；最新留白颜色及声音、控制仍待实机验收。

## 真机验收清单

1. 同一 Wi-Fi 下点击 DLNA 图标，在 Android B 站视频页点 `TV`，确认列表可见 `AnyDeck DLNA`。
2. 选择接收端，确认视频和声音实际播放；分别验证 MP4 与 HLS 来源，以及暂停、继续、进度跳转、音量和停止。
3. 手机切换 Wi-Fi、电脑睡眠/唤醒、断开网络后重新启用，确认服务可重新被发现，无遗留端口占用。
4. 关闭播放器窗口与关闭 DLNA 开关，确认手机端状态更新、电脑停止播放。
5. 验证 macOS Light/Dark 下图标状态与中英文文案；确认 Android scrcpy 与 iOS AirPlay 原有操作不受影响。
