# 屏幕投屏、摄像头、麦克风、剪贴板：纯 Rust 底座与 Flutter UI

## 业务目标及全架构大一统（路线 A）

本项目已彻底清除所有 C++ / Objective-C++ 代码并删除 `scrcpy_flutter` 插件，全桌面端统一为 **Flutter (Dart) + Swift / Metal 原生桥接 + 纯 Rust 底座 (`rust/device_bridge/`)** 架构：

- **屏幕投屏 (Screen Mirroring)**：纯 Rust 建立视频流与音频流，纯 Rust 调用 Apple VideoToolbox 硬解并将 `CVPixelBuffer` 注册至 Metal Flutter Texture；音频通过纯 Rust AudioQueue 直通播放。
- **触控与反向控制 (Control Socket)**：触控、鼠标移动、滚轮、文本输入、按键注入通过 Rust 内部 `control_socket` 直接向 scrcpy-server 发送大端二进制控制协议。
- **摄像头与麦克风**：前后摄像头硬解预览；麦克风独立采集与监听静音。
- **手机剪贴板**：双向监听与复制。
- **资源生命周期**：切页、关闭投屏独立窗口、关闭弹窗、设备离线或断连，由 Rust `AtomicBool` 取消标志和 Drop 统一回收子进程与 socket，Swift 侧窗口关闭时释放对应 Texture。

## 平台和版本兼容

| 功能 | Android 门槛 | 页面和运行时处理 |
| --- | --- | --- |
| 屏幕投屏 | Android 5 / API 21+ | 支持全分辨率自适应与横竖屏旋转 |
| 摄像头 | Android 12 / API 31+ | 版本不足禁用开始；其他 App 占用仍可能失败 |
| 麦克风 | Android 11 / API 30+ | Android 11 启动前需解锁；API 29 及以下禁用；系统隐私开关、通话和录音并发可能导致静音 |
| 文本剪贴板 | Android 5 / API 21+ | Android 10+ 普通后台 App 限制不能套用于 scrcpy；实际 ROM、锁屏、工作资料兼容性需验证 |

本轮 Rust 库、AudioQueue、VideoToolbox 和 Flutter Texture 打包只接入 macOS，其他电脑平台禁用上述入口。UI 从全局设备 Registry 读取 SDK；版本未知时禁用，不猜测为支持。Rust 启动时再次执行 getprop 校验，防止 UI 缓存过期。

版本满足不代表已真机验证。剪贴板只支持文本；Android 清空剪贴板时 scrcpy 不一定推送事件，所以 UI 展示的是最近收到的文本，不能保证反映系统清空后的空值。

## 架构与实现文件

- `rust/device_bridge/src/adb.rs`：Rust std::process 调用 ADB，处理超时、取消、server 进程和独立转发端口。
- `rust/device_bridge/src/worker.rs` / `stream.rs`：TCP 握手、拆包、控制协议写入、RAW 音频、H.264/H.265 帧读取。
- `rust/device_bridge/src/video.rs` / `video_ffi.rs`：Rust 调用 VideoToolbox，处理 Annex-B→AVCC、SPS/PPS、解码和 CVPixelBuffer 所有权。
- `rust/device_bridge/src/audio_queue.rs`：Rust 调用 macOS AudioQueue，固定 buffer 池、播放静音与析构。
- `rust/device_bridge/src/lib.rs`：C ABI 导出 (`anydeck_start_mirror`, `anydeck_send_control`, `anydeck_stop`, `anydeck_release` 等)。
- `lib/core/scrcpy/rust_device_bridge.dart`：dart:ffi 统一绑定，不解析设备协议。
- `lib/core/scrcpy/embedded_scrcpy_service.dart`：投屏服务入口，通过 `MethodChannel('anydeck/rust_texture')` 注册纹理并调用 Rust。
- `lib/core/scrcpy/rust_device_session.dart`：Flutter 句柄状态适配；100ms 查询本机 Rust 内存状态，不轮询 ADB。
- `lib/features/control/embedded_scrcpy_viewer.dart`：触控、滚轮、按键控制事件收口并调用 provider。
- `macos/Runner/RustTexturePlugin.swift`：平台必需的纯 Swift 薄桥接，仅 Texture 注册、Metal 显存帧通知与窗口关闭资源追踪。

彻底移除了原 `scrcpy_flutter` 插件及全部 C++/Objective-C++ 依赖，FFmpeg 静态库已完全剥离。

## 会话参数与协议

每次会话使用不同 scid、`adb forward tcp:0` 原子分配端口以及 `/data/local/tmp/anydeck-<scid>.jar`，防止多功能同时推送同一个 jar 时覆盖正在读取的内容。始终使用用户选中的 ADB serial。

共享 server 4.0，`tunnel_forward=true`、`send_device_meta=false`、`send_dummy_byte=true`、`power_on=false`。

| 会话 | 关键 server 参数 |
| --- | --- |
| 摄像头 | `video=true audio=false control=false video_source=camera video_codec=h264 camera_fps=30 max_size=1280 video_bit_rate=4000000 camera_facing=front/back` |
| 麦克风 | `video=false audio=true control=false audio_source=mic audio_codec=raw send_frame_meta=false` |
| 系统播放音频 | `video=false audio=true control=false audio_source=output audio_codec=raw send_frame_meta=false` |
| 剪贴板 | `video=false audio=false control=true clipboard_autosync=true` |

- RAW 音频：dummy byte 后验证 codec `raw`；48kHz、双声道、16-bit PCM，20ms/3840 字节一块。网络接收和播放都在 Rust 线程内，不把 PCM 逐包发给 Flutter。
- 摄像头：验证 codec `h264`；v4 session metadata 是独立 12 字节头；帧长度最大 4MiB。VideoToolbox 输出 BGRA CVPixelBuffer，Flutter Texture 直接读取，无 Base64/逐帧 Dart 拷贝。
- 剪贴板：首次及刷新发送 `[8, 0]`（GET_CLIPBOARD、COPY_KEY_NONE）；服务端 `type=0 + uint32 大端长度 + UTF-8`。最大 256KiB，只保存最近一份内容和 revision，Flutter 合并高频展示更新。

## 生命周期与性能

Rust 每会话一个工作线程，状态 0 启动中、1 已有实际画面/声音或剪贴板连接、2 已停止、3 异常结束。停止发出原子取消信号并 shutdown socket，随后 Drop 终止/reap 子进程、移除本会话端口及远端 jar。

macOS 屏幕投屏只有在 VideoToolbox 产出首个非零尺寸且带 `IOSurface` 的 `CVPixelBuffer` 后才进入状态 1；socket 建立完成仍保持启动中。解码错误或缺少 `IOSurface` 会让会话进入状态 3，并输出 `[RustDeviceBridge] mirror worker ERR`，不能吞掉错误后把黑色 Texture 当作成功。Flutter 3.47 默认启用的 Impeller 在 macOS External Texture 路径存在偶发黑屏，本项目在 `macos/Runner/Info.plist` 显式设置 `FLTEnableImpeller=false`，投屏暂时使用 Skia；后续升级 Flutter 时必须经过多窗口、旋转和重复启停真机回归后才能重新启用。

ADB 单条命令上限 15 秒，输出排空且最多保留 4096 字节；端口分配返回后才处理取消，异常时通过本次唯一 socket 补查映射。整个启动有 75 秒上限，停止异常清理最多等待 65 秒，UI 始终显示正在连接/停止。

Android PCM 播放器固定 8 个 16KiB buffer，通常每包 20ms，预填 3 包后启动；池满时丢弃新块，持续 500ms 无回收则重建输出。Swift 每秒最多通知 30 次纹理可用。VideoToolbox 同步解码，Rust 持有最新一帧并在替换时 release；AudioQueue Dispose 不持有回调锁，避免死锁。

多窗口不共享 Riverpod 状态；Rust 库按全局句柄隔离会话。每个 Flutter Engine 向其窗口的薄 Swift 桥接登记句柄，窗口关闭时统一 release，防止 Isolate 退出后遗留音频采集或剪贴板线程。

## 控制页后台音频与设备操作（2026-10-13）

- “只转发音频”使用独立 Rust 系统播放音频 Session，不启动外部 `scrcpy` CLI、不创建视频 Texture 或投屏窗口。底层仍复用应用内置 `scrcpy-server.jar` 的 Android 音频采集协议，不能表述为完全不使用 scrcpy 协议。
- 音频按钮区分 idle、starting、active 和 stopping；设备离线、Provider 销毁或后台 Session 退出时回收资源并恢复 idle，避免按钮显示运行但后台已结束。
- Android/HarmonyOS 控制页补充锁屏、截图和录屏入口。锁屏只执行 suspend，不在已息屏时反向唤醒；截图按 ADB/HDC 分流并保存、复制；录屏复用设备级 `screenRecordProvider` 的启停、时长和保存流程。iOS 不展示这些 Android/HarmonyOS 操作。

## 构建与依赖

独立 Rust crate 无第三方依赖。macOS 的 `Embed Native Dylibs` 阶段自动调用：

```bash
bash script/build_device_bridge.sh
```

生成 `libanydeck_device_bridge.dylib` 并随 App 签名打包，不提交机器生成的二进制。脚本支持 ARCHS 指定 arm64/x86_64，非当前架构需预先安装相应 Rust target；当前项目 Xcode 配置为 arm64。本轮实际只验证当前 arm64 构建。

Flutter 测试替换 backend，无需动态库。独立 FFI 测试可以显式使用 `ANYDECK_DEVICE_BRIDGE` 指向生成库；正式 App 从 Contents/Frameworks 加载。

## 验证与交接

摄像头预览入口从应用页的使用时长弹窗迁到 Android 控制 Tab 快捷操作区。点击“摄像头”打开 `CameraPreviewDialog`，内部复用 `CameraPreviewView` 与现有独立 Rust 会话；打开弹窗不自动启动摄像头，关闭后由 autoDispose 回收。HarmonyOS 与 iOS 不显示入口；使用时长弹窗仅保留使用统计与位置记录。

迁移验收：控制 Tab 打开弹窗，分别预览前后摄像头并停止；关闭弹窗后确认会话释放，再与投屏并行验证。静态测试无法替代真机摄像头与系统权限提示验收。

执行结果和人工回归见 [adb-device-rust-sessions-test.md](adb-device-rust-sessions-test.md)。尚未运行桌面项目或访问真实设备摄像头/麦克风，实际采集、ROM 权限和长时间并发需要真机回归。

协议依据：[scrcpy 4.0](https://github.com/Genymobile/scrcpy/tree/v4.0)、[audio](https://github.com/Genymobile/scrcpy/blob/v4.0/doc/audio.md)、[camera](https://github.com/Genymobile/scrcpy/blob/v4.0/doc/camera.md)、[Controller](https://github.com/Genymobile/scrcpy/blob/v4.0/server/src/main/java/com/genymobile/scrcpy/control/Controller.java)。

## Android 音频恢复与无线弱网降级（2026-10-29）

### 需求与诊断边界

用户反馈投屏播放一段时间后静音，重新连接恢复，并要求弱网时降低分辨率和传输码率。源码确认原 Android AudioQueue 创建、静音、入队失败被投屏线程忽略，池耗尽后无限丢包，音频 socket 结束也没有上报恢复。这些是可确认的恢复缺口；没有故障现场原生日志，不能认定它们是本次真机静音的唯一原因。

### 实现与性能

- `audio_queue.rs`：预填 3 个 buffer 后才 Start；检查入队/启动 OSStatus，失败 buffer 归还池；每 250ms 检查 IsRunning，满池 500ms 无回收报告停滞。Dispose 仍在不持 pool 锁的情况下等待 callback 结束。
- `pcm_playback.rs`：输出创建、静音、入队失败后释放旧输出，以至少 500ms 的创建间隔重试；超过 1.5 秒无 PCM 后重建本机队列。恢复前应用最新静音值，继续排空 socket，不积压音频。投屏与独立麦克风/系统音频共用该恢复层；独立音频保留首次创建失败的错误返回，后续读包允许暂停并响应取消。
- `mirror_audio.rs`：记录音频收包错误；只有已收到 PCM 后意外结束才设置 audioFailed，启动即不支持采集不触发重连。正常主动停止不触发恢复。
- `mirror_health.rs`：视频 PTS 与接收端单调时钟的相对偏差估算新增积压，不要求手机与电脑对时。PTS 回退重置基准，超过 1.5 秒无更新的样本作废；`stream.rs` 另监测正在接收的 payload，持续收不完半帧也能上报积压。等待下一帧不判断拥塞，因此静态画面、暂停或低 FPS 不直接触发降级。
- `anydeck_mirror_health`：低 32 位为积压毫秒，bit 32 为音频意外退出。Flutter 每秒读一次本机 FFI；旧 dylib 缺少该接口时返回 null、禁用自动监测，不新增 ADB 网络探测，不向 Dart 逐帧传递数据。
- `mirror_stream_health.dart`：连续 3 次积压 ≥350ms 才在 TCP/TLS Wi-Fi 投屏下降一档，重建决策至少间隔 20 秒；USB 不自动降画质。参数同时受用户配置上限约束，不会反向增大任何值。

| 档位 | 最长边上限 | 视频码率上限 |
| --- | --- | --- |
| 第一档 | 1280 | 4 Mbps |
| 第二档 | 960 | 2 Mbps |
| 第三档 | 640 | 1 Mbps |

`max_size` 指最长边，不是“720p/1080p”的短边。音频继续使用 48kHz、16-bit、双声道 RAW，数据率约 1.536 Mbps；此次通过降低视频负载给音频留带宽，没有降低音频码率。带宽不足以承载 RAW 音频、设备端采集权限/DRM、输出设备异常等情况仍可能不流畅。

### 会话与兼容

- `embedded_scrcpy_recovery.dart` / `embedded_scrcpy_providers.dart` 复用已有 stop/start，串行清理旧 Texture、Rust handle、server 和 forward，再用相同 deviceId/newDisplay/startApp 建立会话。参数仅写入本次启动，不覆盖 SharedPreferences。
- 当前接入未实现编码参数热更新，调整通过重建生效，画面和音频会短暂中断；这不是无缝切换。音频 socket 异常最多自动重建两次，同样有 20 秒冷却。
- 恢复期间保留最新音频焦点，启动等待过程中收到的静音变化在 Texture 注册完成时补齐。窗口关闭、用户刷新、通道切换会递增 generation 并取消监测，迟到的任务不再拉起旧会话。
- 自动降级只向低档移动，不主动探测升档；手动刷新或切回 USB 用用户原设置重新开始。与现有 USB → TCP → TLS 优选机制协作，不改变通道标签。
- 新增 stderr `[Android Audio]` 与 Dart `[MirrorRecovery]` 诊断；原生 stderr 不等于已经写入 Dart 本地日志。需要重新编译打包 native dylib 才能获得新行为；本轮只构建 crate，没有覆盖正在运行的 App。

验证与未验收项见 [adb-device-rust-sessions-test.md](adb-device-rust-sessions-test.md)。
