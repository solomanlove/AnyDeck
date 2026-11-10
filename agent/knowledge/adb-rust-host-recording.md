# Rust 电脑本地音视频录制（scrcpy-server 4.0）

## 需求与范围

电脑本地录制直接使用内置 scrcpy-server 4.0 与 Rust 引擎，移除外部 `scrcpy --no-window --record` 调用。覆盖截图录屏页、设备控制/投屏工具栏的设备级录屏、批量录屏三个入口；默认自动决策及“强制电脑本地录制”设置保持有效。普通设备端 `screenrecord`、HarmonyOS HDC、iOS USB 录制和融合副屏的设备端录制保持原路由。

这是源码改动，未发布新 Release；已发布 v1.0.1 安装包不会自动获得此功能，官网也没有提前更改版本或截图。

## 架构与接入

```text
内置 server 4.0（Android 编码 H.264 + AAC）
  -> 两路 ADB forward socket
  -> Rust 长度校验/拆包 -> 有界队列 -> MP4 封装 -> 电脑文件
```

- `rust/device_bridge/src/recording/protocol.rs`：4.0 codec 标识、12 字节 session/media header、配置与关键帧标志、Annex-B NAL 拆分。
- `muxer.rs`：纯 Rust `mp4 = 0.14.0`，H.264 Annex-B 转 AVCC，读取 SPS/PPS 与 AAC-LC AudioSpecificConfig，直接封装压缩包。无需 FFmpeg 动态库/CLI，也不经过 Flutter Texture 解码重编码。
- `receiver.rs`：独立视频/音频收包线程和单一文件写入线程；不共享投屏会话。ADB server、临时 JAR 与端口复用既有 `adb::Transport` 的所有权与 Drop 清理。
- `mod.rs`：导出 `anydeck_start_recording`、`anydeck_recording_error`；复用 `anydeck_status/stop/release`。全局句柄与设备会话统一分配，按设备 serial 阻止重复本地录制。
- Dart `host_recording_backend.dart` 提供可替换工厂；`rust_recording_api.dart` 只传路径/句柄/错误，媒体包不逐帧穿过 FFI；`rust_host_recording.dart` 处理启动、轮询、取消、收尾与窗口跟踪。
- 三个入口均等待 backend `stop()` 完成后才提示保存成功或移动文件，已删除 `ScrcpyService.startRecording`，没有外部 CLI 回退。

新增依赖及许可证位于 `assets/scrcpy/rust-recording-licenses.txt`，由既有 assets/scrcpy 资源清单随 App 分发。固定编码测试数据只在 Rust tests 编译时包含，不进入 Release 动态库。

## 参数与行为

- 独立 server：`video=true audio=true control=false video_codec=h264 audio_codec=aac audio_bit_rate=128000 video_bit_rate=8000000 capture_orientation=@`。不修改现有投屏的 `audio_codec=raw`、音频焦点、控制通道或显示会话。
- 分辨率采用设备端默认值；不额外强制降低尺寸/FPS。锁定初始捕获方向，旋转时保留同一录制画布；若折叠/显示模式切换导致真实尺寸或 SPS/PPS 变化，则明确终止并保留部分文件，不能把不兼容参数写入同一轨道。
- 视频以第一个有效 IDR 关键帧为起点。丢弃该点之前的音频，之后使用设备 PTS 作为公共时间基准，以 90 kHz 时基及轨道偏移保持同步；非单调时间戳报错。最后一帧可保持到停止时间，ADB 清理耗时不计入视频时长。
- AAC-LC 音频由手机编码。设备明确禁用音频（例如 Android 10 及更旧）时允许静音视频；设备编码配置错误、AAC 配置异常、途中音频断开则失败，不能无条件宣称录到了声音。Android 11 启动时通常需要解锁，受 ROM/应用采集限制影响。
- 纯本地录制移除 UI 的固定 180 秒自动停止。设备端和包含设备端录制的混合批次仍保留既有 180 秒限制。
- 当前 Flutter Rust 动态库加载仅支持 macOS；实现没有新增 CPU 架构专用代码，仍由既有 arm64/x86_64 Actions 各自构建。其它桌面平台不新增外部 scrcpy 回退。

## 生命周期、错误与内存

1. 启动先校验目标文件；使用 `create_new` 建立 `*.partial.mp4`，避免覆盖已有文件或临时文件。启动成功必须收到有效视频及可用 AAC（或设备明确禁用音频），不能把 socket 连通当作成功。
2. 收包队列固定 8 项，每包最多 8 MiB；超过容量立即显式失败，不静默丢弃压缩帧。启动前音频最多 128 包，每包最多 32 KiB。MP4 索引总样本数限制 2,000,000，防止长期录制导致元数据无限增长；达到限制时保留部分文件并报告失败。
3. Header 空闲等待可中断，单个 payload 有 5 秒读取上限，连接有 15 秒期限。ADB 单条命令沿用 15 秒期限；Dart 启动最多 75 秒，停止/清理等待最多 70 秒。
4. 停止设置取消标志、shutdown 本会话 socket、排完已接收包、join 收包线程、回收 server/forward/JAR，再写完 MP4 尾索引并 flush/sync。原生状态只有在文件与资源收尾后才变为成功停止。
5. 正常结束通过 macOS 排他重命名公布目标文件名（禁止覆盖，也不要求磁盘支持 hard link）。断线/编码变化等异常仍尝试写尾索引，保留可播放的 `*.partial.mp4` 并反馈路径；写盘失败或强制杀死 App 时不能保证临时文件完整。无任何关键帧的空文件会清理。
6. 启动/停止幂等；Provider 或页面销毁会取消并异步回收，迟到的启动不再更新 UI。窗口通过既有 `track/untrack` MethodChannel 跟踪句柄，不增加跨 Isolate 全局设置广播；同设备重复录制由 Rust 注册表拦截。
7. 设备级后台错误进入状态并由工具栏/控制页现有 Toast 提示；截图页沿用本地化 SnackBar；批量页保留每台设备错误且不将失败文件列为保存成功。

## 测试与验证

自动化内容：

- Rust 固定 H.264/AAC 数据写入真实 MP4 后读回，检查双轨、样本数、尺寸、首帧及音轨偏移；禁用音频与异常收尾的部分 MP4 仍可读。
- 拆包验证分片 header、超大包先于分配拒绝、三/四字节 Annex-B、AAC 配置拒绝、PTS 回退、启动音频缓存上限、写队列满、禁止覆盖与尺寸变化。
- 本地双 socket 与模拟 ADB 的 C ABI 集成测试，实际启动/停止录制线程、检查同设备重复启动拒绝、server 4.0/AAC 参数以及结束前 forward/JAR 清理。测试不访问手机。
- Dart fake-native 验证幂等、等待收尾、启动/写盘错误、取消、超时与跟踪注销；Provider 验证强制/自动回退、同一入口防重、后台断线、销毁及副屏路由；截图页 widget tests 验证保存成功/失败提示与销毁后的 UI 回调隔离。
- FFmpeg 仅作为开发验证工具生成固定测试流和独立解码产物，不属于运行依赖。`ffprobe` 确认 H.264/AAC 双轨，完整解码无错误。

```bash
cargo test --manifest-path rust/device_bridge/Cargo.toml --lib
flutter test --no-pub test/rust_host_recording_test.dart test/host_screen_record_provider_test.dart test/screenshot_host_recording_test.dart
flutter analyze --no-pub
ANYDECK_TARGET_ARCH=arm64 FLUTTER_XCODE_ARCHS=arm64 flutter build macos --release --no-pub
ANYDECK_RECORD_TEST_OUTPUT=/tmp/anydeck-recording.mp4 cargo test --manifest-path rust/device_bridge/Cargo.toml recording::tests::real_h264_aac
ffprobe -v error -show_streams /tmp/anydeck-recording.mp4
ffmpeg -v error -i /tmp/anydeck-recording.mp4 -f null -
```

## 真机验收清单

设备离线，本轮不启动桌面 App、不访问手机；以下仍需后续验收：

1. Apple Silicon 与 Intel 实机分别开启强制电脑录制，确认 MP4 画面和系统声音、QuickTime 播放、停止后文件可立即打开。
2. USB/Wi-Fi、不同 ROM、Android 11 锁屏/解锁、设备禁用音频与应用限制采集。
3. 同时投屏与录制，确认投屏画面/控制/RAW PCM 播放不回归，并检查手机对并行采集的支持。
4. 长时间录制、磁盘空间不足、途中拔线、停止期间关闭页面、重复启停及多设备批量收尾。
5. 横竖屏旋转、折叠展开和分辨率改变；确认固定方向或错误/部分文件提示与上述边界一致。

## 本轮执行结果（2026-11-10）

- Rust 默认 features 的全部单元测试：68 passed、1 ignored。忽略项是既有 `video::native_tests::decode_generated_frame`；本次新增录制用例均执行通过。
- Flutter：15 项新增生命周期/Provider/页面测试，加上投屏恢复、音频健康、设置、截图编辑和融合副屏回归，共 55 项通过。
- 修改范围 `flutter analyze --no-pub` 无问题。全仓 analyze 为 38 项既有 warning/info，均在本次未修改的文件中，未进行无关修复。
- 本机默认 Xcode 架构解析为 arm64e，直接构建被 Flutter 引擎 slice 校验阻断；改用与 CI 一致的 `ANYDECK_TARGET_ARCH=arm64 FLUTTER_XCODE_ARCHS=arm64` 后 Release 构建成功（104.7 MB），没有修改项目架构配置。
- App 包内 35 个 Mach-O 的 arm64 slice、ad-hoc 签名与依赖验证通过；确认导出两个录制 C ABI 符号，新增许可证资源已进入 Flutter assets。
- 独立 `ffprobe`/FFmpeg 解码确认固定 MP4 具有 10 帧 H.264 和 48 帧 AAC、音轨偏移 20 ms；解码音频非静音（98,304 个声道采样值，RMS 约 0.0616）。FFmpeg 不属于 App 运行依赖。
- 没有启动桌面 App，没有进行 Intel 原生运行、真实手机采集、长时间录制或实际拔线验收；不将构建/模拟协议测试当作这些验收的替代。
