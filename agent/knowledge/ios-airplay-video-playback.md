# AirPlay 视频媒体播放窗口

## 目标与原因（2026-10-27）

用户从 iPhone 哔哩哔哩点击 AirPlay 后只有声音，没有视频窗口。代码确认原接入显式关闭 Bonjour Video/HLS 能力位，未启用 UxPlay HTTP 视频路由，也未注册媒体播放回调；原窗口仅由 H.264 屏幕镜像首帧触发。此缺口与 App 内视频投放的使用路径一致，但尚未取得本次 B 站实际 `/play` 请求和无线播放证据，不能把代码原因分析当成真机验收。

## 镜像与视频窗口分流（2026-10-28）

- 需求：iPhone 6s 已选择屏幕镜像却没有窗口；按实际协议类型打开手机镜像窗口或视频播放器。
- 原缺口：Dashboard 仅监听 `Mirroring` 首次变化，依赖解码首帧且开窗失败无重试；创建子 Engine 成功也不等于窗口已就绪。无法仅凭旧日志确定本次旧进程缺失画面的唯一原因，不能将这些代码缺口当作完整故障复现。
- RTSP type 110 镜像启动回调新增 `MirrorStarting=3`，先打开手机镜像窗口并显示等待画面。首个有效 IOSurface 后进入 `Mirroring=1`；FFI 轮询也检查异步首帧，避免最后一包返回后才完成解码时一直停留在等待状态。重置回到 Idle，Stopped 不可被延迟回调复活。
- `AirPlayMirrorWindowCoordinator` / `airplayWindowRoutingProvider` 由主 Isolate 持有，首次订阅立即核对现有会话；同一连接单飞开窗、失败每 3 秒重试，断开/换客户端后重新处理。开窗通过 `isFlutterReady` 和 `switchIosMirrorSource` 确认，再显示窗口；复用同设备 USB 窗口的规则保持。
- `/play` HTTP(S) 媒体仍由 `AirPlayVideoPlayer` 路由到独立原生播放器。音频不会触发手机窗口或视频窗口；普通 App 在屏幕镜像中播放视频，仍属于手机镜像，不按画面内容猜测类型。
- 手机窗口标题为「设备名 · AirPlay 手机镜像」，视频窗口为「接收端名 · AirPlay 视频」，中英文和系统标题同步。接收页分别显示镜像/视频状态及恢复窗口入口，可同时展示两种会话。
- 帧仍通过 native Texture 传递；状态轮询仅传递状态/尺寸/客户端元数据，日志不记录媒体 URL。

### 本次验证

- Dart 定向测试 38 项通过，覆盖：首帧前开窗、已有会话订阅、单飞与失败重试、重连/多槽位、视频与音频不误开手机窗口、Engine 就绪/切源确认、视频活动回调和标题、接收页双入口，以及原 DLNA 回归。
- Rust：39 passed / 1 ignored；包括真实 VideoToolbox 测试帧的 `MirrorStarting → Mirroring → Idle`、无首帧重置和停止后不复活，原 HTTP 视频协议回归通过。
- 定向静态检查无问题；最终 macOS Debug 构建通过。Dashboard 存在既有 `liquid_glass_background.dart` 未使用导入警告，本次未修改该无关代码。
- 原生播放器 smoke：MP4/HLS 首帧、进度、暂停/跳转/恢复、DLNA 窗口独立性、加载失败暂停均通过。
- 真机：2026-10-27 22:43，运行 build/macos/Build/Products/Debug/AnyDeck.app（PID 66255），iPhone 6s / iOS 15.8.8 重新连接。日志记录 `idle → mirrorStarting → mirroring`、608×1080 首帧及 Texture 首次拷贝；实际窗口先显示手机控制中心，随后更新到手机桌面。用户明确确认「画面同步正常」，持续观察超过 1 分钟未断开。
- 最后的系统标题同步与切源应答检查由定向测试和构建验证；未再次打断已正常镜像的手机。B 站 HTTP 视频实际投放、USB→AirPlay 复用窗口及多手机并发仍需独立真机回归，不由单台镜像验收替代。
- 诊断文件（本机临时）：`/tmp/anydeck-airplay-type-runtime.log`、`/tmp/airplay-type-final-tests.log`、`/tmp/airplay-type-rust-tests.log`、`/tmp/airplay-type-native-smoke.log`、`/tmp/airplay-type-final-analyze.log`、`/tmp/airplay-type-final-build.log`。历史 `socket 48` 为固定端口被占后动态端口成功监听的残留日志；这次不能据此判定接收器启动失败。

### 回归路径

1. 控制中心开始/结束/重新开始屏幕镜像，检查只出现一个手机窗口，首帧等待态不会假报断开。
2. 视频 App 发起 HTTP 视频投放，检查独立视频窗口和「打开视频窗口」入口；纯音频不弹空视频窗口。
3. 镜像与视频互切、已有 USB 手机窗口时切镜像、模拟慢 Engine/切源失败，检查没有重复窗口或永久漏开。
4. 接收页离开/返回、关闭并恢复视频窗口、切换中英文，检查状态、标题和播放进度。

## 数据流与模块

```text
iPhone 视频 App → AirPlay HTTP /play、/rate、/scrub、/stop
  → UxPlay（直连 HTTP(S) 媒体 / FCUP HLS playlist）
  → native/uxplay_media_callbacks.h → Rust MediaState
  → anydeck_airplay_copy_media_state / anydeck_airplay_update_media_state
  → AirPlayVideoPlayer（300 ms 单飞轮询）
  → any_deck/airplay_player
  → 独立 DlnaPlayerBridgeService.airplay → NSWindow + AVPlayerLayer
```

- AirPlay 与 DLNA **复用窗口实现、各自持有播放器实例与 MethodChannel**。关闭 AirPlay 不会结束 DLNA。原 USB/WDA、镜像 Texture 和音频 AudioQueue 路径保留。
- 视频窗口跟随接收端名称，复用系统全屏、可调整大小、原比例显示和标题栏图钉；加载、错误、图钉文案由当前语言提供。音频开关同时控制 AudioQueue 和视频播放器静音。
- 播放、暂停/继续、跳转、停止与实际进度回读已接入；初始进度在 AVPlayerItem 就绪后应用。错误留在播放器窗口，不挤压手机镜像窗口。
- `MediaState` 只保留最新目标，不积累事件队列；generation 隔离换源回调，seek_revision 区分跳转与普通进度更新。实际进度不修改命令 revision。
- 服务关闭等待正在执行的窗口调用收尾，再关闭窗口、销毁 native 服务；原有 Notifier 从 `airplay_server_service.dart` 原样拆到同目录 `airplay_server_notifier.dart`，防止单文件继续超过 500 行。
- FFI 快照有界，URL 限制 HTTP(S) 与长度；日志不输出签名媒体地址。接收端本来允许 LAN 设备发起播放，不新增远端执行命令。

## UxPlay 接入注意事项

- Video/HLS 能力位与实际回调一起启用，镜像 HEVC 能力位仍关闭。
- HTTP 媒体回调的 cls 是全局 server，RTSP 回调的 cls 是连接对象，两者不可混用。HTTP 错误/结束路径改用连接回调，EOS 使用全局媒体 stop。
- 直连 HTTP(S) Content-Location 不需要 playlist UUID，也不经过旧 FCUP playlist 地址缓存。仍沿用上游 binary plist `/play` 协议；本次没有承诺兼容所有旧 text/parameters 请求。
- 对播放请求 plist 类型、Session ID/FCUP UUID 长度及缺失参数做校验，防止原断言/空指针导致接收进程退出。
- 当前一个广播接收器支持一个 HTTP 视频播放器；镜像的多槽位机制保持原状。媒体播放不假报 `Mirroring` 或伪造 Texture 尺寸。

## 验证命令与结果

```bash
cargo test --manifest-path rust/device_bridge/Cargo.toml --lib
cargo test --manifest-path rust/device_bridge/Cargo.toml --lib --no-default-features
flutter analyze --no-pub lib/core/airplay lib/core/dlna \
  lib/app/l10n/tables/app_l10n_ios_tools.dart test/core/airplay \
  test/airplay_native_integration_test.dart
flutter test --no-pub test/core/airplay test/core/dlna \
  test/airplay_server_service_test.dart test/airplay_connection_monitor_test.dart
ANYDECK_DEVICE_BRIDGE="$PWD/macos/Libs/libanydeck_device_bridge.dylib" \
  flutter test --no-pub test/airplay_native_integration_test.dart
python3 test/native/run_airplay_video_smoke.py
flutter build macos --debug --no-pub
```

- Rust 默认：39 passed / 1 ignored；无默认 feature：35 passed / 1 ignored。原有 ignored 测试未算作通过。
- Native TCP 测试实际经过 UxPlay HTTP parser 和 C/Rust 回调：验证能力位、MP4/HLS 地址、无 UUID 的直连视频、暂停/继续、跳转、进度、停止、换源、无效 plist 和缺失参数。
- Dart 定向回归 22 项通过，覆盖旧播放失败不能结束新媒体、异步开窗期间停止、旧代次关窗事件、纯音频不弹视频窗口，并包含 DLNA 回归。
- 真实 dylib FFI 启停/跨 Isolate/媒体快照验证 1 项通过；Texture 通道仍使用 mock，不代表镜像画面验收。
- 原生 smoke 使用真实项目 AVPlayer/NSWindow 和模拟消息传输：本地 HTTP MP4/HLS 均产生 `AVPlayerLayer.isReadyForDisplay`，实际进度前进，初始定位、暂停、跳转、恢复、关闭 AirPlay 后 DLNA 保持播放均通过；不可访问媒体的失败状态与暂停播放也已验证。测试样片现场生成，测试窗口静音，不启动 AnyDeck 主程序；需要 macOS 图形会话、Flutter SDK、Xcode Command Line Tools、ffmpeg、Python 3。HTTP 测试服务必须正确支持 Range/206，否则 AVPlayer 可能直接拒绝 MP4。
- 定向静态分析、macOS Debug 构建通过；新构建必须完整重启才能加载新的 native 能力和 FFI 符号。

## 哔哩哔哩真机回归与边界

1. 完整重启新构建，开启“投屏接收”中的 AirPlay；iPhone B 站回到视频页重新选择接收端，不能沿用旧会话。
2. 确认打开以接收端名称命名的视频窗口，实际画面和声音连续播放；日志出现 `[AirPlay Video] opened generation=...` 只证明提交了播放请求，还须以实际首帧和进度确认。
3. 手机暂停、继续、跳转、切换两条视频，再结束投屏；确认无旧视频抢占、无残留声音。并行 DLNA 视频不应被 AirPlay 停止。
4. 对“只发音频”、DRM、额外鉴权/HTTP headers、无法访问的 CDN 地址分别诊断；不可把所有 B 站内容都算作已兼容。当前 AirPlay 视频使用 AVPlayer，不自动复用 DLNA 的 libmpv 回退。
5. 本次未启动完整 AnyDeck App，**尚未完成 B 站 iPhone 无线投放验收**；已完成的是协议、FFI、窗口播放器和构建验证。

参考：[UxPlay 上游说明](https://github.com/FDH2/UxPlay)；固定 vendor 版本与本地补丁见 `rust/device_bridge/vendor/uxplay/UPSTREAM.md`。
