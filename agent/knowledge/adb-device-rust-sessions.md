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
| 剪贴板 | `video=false audio=false control=true clipboard_autosync=true` |

- RAW 音频：dummy byte 后验证 codec `raw`；48kHz、双声道、16-bit PCM，20ms/3840 字节一块。网络接收和播放都在 Rust 线程内，不把 PCM 逐包发给 Flutter。
- 摄像头：验证 codec `h264`；v4 session metadata 是独立 12 字节头；帧长度最大 4MiB。VideoToolbox 输出 BGRA CVPixelBuffer，Flutter Texture 直接读取，无 Base64/逐帧 Dart 拷贝。
- 剪贴板：首次及刷新发送 `[8, 0]`（GET_CLIPBOARD、COPY_KEY_NONE）；服务端 `type=0 + uint32 大端长度 + UTF-8`。最大 256KiB，只保存最近一份内容和 revision，Flutter 合并高频展示更新。

## 生命周期与性能

Rust 每会话一个工作线程，状态 0 启动中、1 已有实际画面/声音或剪贴板连接、2 已停止、3 异常结束。停止发出原子取消信号并 shutdown socket，随后 Drop 终止/reap 子进程、移除本会话端口及远端 jar。

ADB 单条命令上限 15 秒，输出排空且最多保留 4096 字节；端口分配返回后才处理取消，异常时通过本次唯一 socket 补查映射。整个启动有 75 秒上限，停止异常清理最多等待 65 秒，UI 始终显示正在连接/停止。

播放器固定 5 个 20ms buffer（最多约 100ms 队列），满时丢弃新块。Swift 每秒最多通知 30 次纹理可用。VideoToolbox 同步解码，Rust 持有最新一帧并在替换时 release；AudioQueue Dispose 不持有回调锁，避免死锁。

多窗口不共享 Riverpod 状态；Rust 库按全局句柄隔离会话。每个 Flutter Engine 向其窗口的薄 Swift 桥接登记句柄，窗口关闭时统一 release，防止 Isolate 退出后遗留音频采集或剪贴板线程。

## 构建与依赖

独立 Rust crate 无第三方依赖。macOS 的 `Embed Native Dylibs` 阶段自动调用：

```bash
bash script/build_device_bridge.sh
```

生成 `libanydeck_device_bridge.dylib` 并随 App 签名打包，不提交机器生成的二进制。脚本支持 ARCHS 指定 arm64/x86_64，非当前架构需预先安装相应 Rust target；当前项目 Xcode 配置为 arm64。本轮实际只验证当前 arm64 构建。

Flutter 测试替换 backend，无需动态库。独立 FFI 测试可以显式使用 `ANYDECK_DEVICE_BRIDGE` 指向生成库；正式 App 从 Contents/Frameworks 加载。

## 验证与交接

执行结果和人工回归见 [adb-device-rust-sessions-test.md](adb-device-rust-sessions-test.md)。尚未运行桌面项目或访问真实设备摄像头/麦克风，实际采集、ROM 权限和长时间并发需要真机回归。

协议依据：[scrcpy 4.0](https://github.com/Genymobile/scrcpy/tree/v4.0)、[audio](https://github.com/Genymobile/scrcpy/blob/v4.0/doc/audio.md)、[camera](https://github.com/Genymobile/scrcpy/blob/v4.0/doc/camera.md)、[Controller](https://github.com/Genymobile/scrcpy/blob/v4.0/server/src/main/java/com/genymobile/scrcpy/control/Controller.java)。
