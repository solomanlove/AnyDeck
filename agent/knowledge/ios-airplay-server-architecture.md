# iOS AirPlay Wi-Fi 投屏：UxPlay 实验接入与验收边界

## 当前状态（2026-10-09）

用户授权先完成投屏实验，暂不以商业化依赖限制阻塞实现。默认后端已接入 UxPlay 协议核心，提供 legacy 配对、FairPlay 媒体密钥处理、SETUP、NTP 和镜像流解密；H.264 交给现有 VideoToolbox，输出 IOSurface 供 Flutter Texture 使用。没有引入 GStreamer 窗口或改变 Android / iOS USB / WDA 链路。

**代码接入、协议回归和本地解码通过不等于 iPhone 真机投屏通过。** 当前尚未取得本次 iPhone → Wi-Fi → Flutter 窗口连续出画的证据，待按下文验收。独立测试接收端已监听 600 秒，并用 DNS-SD 解析确认名称/实际端口；期间未收到 iPhone 连接请求，计时结束后已关闭。

原截图“无法连接 AnyDeck-AirPlay”没有对应抓包，不能精确断言当时的首次断点。旧 Rust 实现确认缺少 FairPlay key unwrap，并曾有配对算法、分阶段路由和假成功 SETUP 问题；这些旧协议问题已在前次提交修正为正确握手或明确失败。仅使用旧实现仍无法完成加密镜像。

## 待提交代码审查与修复

| 优先级 | 原接入缺陷 / 触发条件 | 修复 |
| --- | --- | --- |
| P1 | UxPlay 启动失败后继续返回旧后端成功；旧后端 SETUP 只能返回 501 | 默认后端失败直接返回错误，禁止静默回退 |
| P1 | `/info` 在 DNS 元数据初始化前可被调用；停止时先销毁 DNS 元数据，协议线程仍访问它 | 先建立 DNS 元数据再开放监听；先 join 所有使用者再销毁元数据；非广播测试也初始化元数据 |
| P1 | DNS 注册、线程创建失败被忽略；跨线程 running 使用普通 bool | 检查同步错误，统一清理；原子标志；仅 join 创建成功的线程，处理 DNS socket 事件 |
| P1 | 第一包即 Mirroring，忽略解码错误；断流保留旧 SPS/PPS 与 CVPixelBuffer | 有效 IOSurface 后才进入 Mirroring；错误进入有界诊断；串行重建 Decoder 并清空 Frame |
| P1 | 回调可能覆盖停止状态，或持有 Server 最后引用导致在 C 线程上自 join | 回调只持有独立 Arc 状态；CAS 禁止 Stopped 回退；native 线程退出后释放上下文 |
| P2 | 接受 HEVC，但解码器只支持 H.264；纳秒时间戳直接传入微秒接口 | 关闭 HEVC/HLS 能力位，拒绝非 H.264；回调 ns → µs |
| P2 | 启停同步等待 native 线程，可能卡住 Flutter UI；stop 持有全局会话表锁 | 后台 Isolate 启停；从表移除后释放表锁，再执行 native stop |
| P2 | 默认 feature 开启后测试构造缺少 native 字段 | 修复构造，补 native TCP 配对、重启、状态与真实 VideoToolbox 回归 |
| P1 | 声称静态链接，但产物仍依赖 Homebrew libcrypto/libplist 路径 | 构建时复制私有名称的静态归档，避免 Darwin 选择同名 dylib；用 otool 检查最终产物 |
| P2 | 构建脚本原地覆盖正在 mmap 的 dylib，并声称运行时即时生效 | 临时文件签名后原子替换；运行中的 App 仍需完整重启 |

## 模块与数据流

```text
iPhone 屏幕镜像
  → 系统 Bonjour (_airplay._tcp / _raop._tcp)
  → UxPlay RTSP / pair-verify / fp-setup / SETUP / timing
  → FairPlay 密钥处理 / 持续镜像流解密 / Annex-B H.264
  → native/uxplay_bridge.c（借用数据、时间单位转换）
  → airplay/uxplay.rs（生命周期、串行解码、状态与错误）
  → video.rs Decoder → CVPixelBuffer / IOSurface
  → 现有 RustTexturePlugin → Flutter 投屏子窗口
```

- `rust/device_bridge/build.rs`：默认 `airplay-uxplay`，编译 vendored C 核心及系统 Bonjour 后端，静态链接 OpenSSL/libplist。
- `vendor/uxplay/UPSTREAM.md`：固定上游 commit、范围和本地补丁。保留根 LICENSE 与源码许可头；导入的第三方原文件不做拆分或全量格式化。
- `native/uxplay_bridge.c`：控制、计时、媒体线程由上游持有；桥接层拥有 Bonjour 事件线程。监听端口冲突时由系统分配新端口，广播实际值，不修改 macOS AirPlay 设置。
- `src/airplay/uxplay.rs`：身份保存至 `~/Library/Application Support/com.github.anydeck/airplay/receiver.pem`，目录 0700、文件 0600；C 回调不持有 Server 本体，stop 返回前 join 完成。
- `src/airplay/mod.rs`：默认 native 后端；`--no-default-features` 仅用于旧 Rust 协议回归，旧 SETUP 仍明确返回缺失 FairPlay 的 501。
- `src/c_api_airplay.rs`：共用 native 会话表和最新错误查询；join 时不占全局表锁。
- `src/video.rs`：只保存最新帧，新增 clear 用于断流清理；解码器原 reset 仍保留内部重配语义。
- `lib/core/airplay/airplay_server_service.dart`：后台 Isolate 启停，通过同一路径加载同一进程动态库；主 Isolate 保持 Texture 注册与 300ms 状态/错误轮询。

声音当前被接收但不播放；当前目标是屏幕镜像出画。HLS、HEVC、DRM 内容和远程触控不属于本次验收。UxPlay 镜像模式允许未使用的 eventPort 为 0，不能把这一点单独判断为协商失败；真正需要工作的 timing/video 通道由上游创建。

## 构建与验证

```bash
brew install pkgconf openssl@3 libplist
cargo test --manifest-path rust/device_bridge/Cargo.toml --lib
cargo test --manifest-path rust/device_bridge/Cargo.toml --lib --no-default-features
cargo build --release --manifest-path rust/device_bridge/Cargo.toml
flutter analyze --no-pub lib/core/airplay test/airplay_server_service_test.dart test/airplay_native_integration_test.dart
flutter test --no-pub test/airplay_server_service_test.dart
ANYDECK_DEVICE_BRIDGE="$PWD/rust/device_bridge/target/release/libanydeck_device_bridge.dylib" \
  flutter test --no-pub test/airplay_native_integration_test.dart
flutter build macos --debug --no-pub
```

`airplay_native_integration_test.dart` 默认跳过，只有显式指定 dylib 才执行；会短暂发布 `AnyDeck-FFI-Regression` 服务。Texture MethodChannel 使用 mock，仅验证跨 Isolate native 会话共享及启停，不证明实际窗口渲染。

2026-10-09 检查记录：默认 Rust 33 passed / 1 ignored；无默认 feature 的旧协议 30 passed / 1 ignored；Dart 状态模型 2 passed；真实 dylib 跨 Isolate 启停重启 1 passed；定向 analyze 无问题（新增文件的 flutter analyze 进程无输出，结束后改用 dart analyze 同样通过）；macOS Debug 构建通过，最终 dylib 的 otool 检查无 Homebrew 动态库依赖。native 测试覆盖真实 TCP `/info`、两阶段签名验证、持久身份、失败启动清理、空闲连接停止/端口释放、无效媒体不得假成功、停止不得被回调复活，以及生成蓝色 64×48 H.264 解码出 IOSurface、清帧并重新解码。生成样本不含用户画面。

## 真机步骤与诊断

独立协议/解码监听（不展示 Flutter 窗口）：

```bash
cargo run --manifest-path rust/device_bridge/Cargo.toml \
  --example airplay_live_test -- AnyDeck-AirPlay-Test 600
```

1. iPhone 和 Mac 使用同一 Wi-Fi，控制中心 → 屏幕镜像 → `AnyDeck-AirPlay-Test`。
2. 观察 native stderr 中连接、协商和首个 decoded IOSurface，以及非零分辨率；仅看到服务名或 RTSP 200 不算出画。
3. 桌面集成验收需要完整重启重新构建后的 AnyDeck，再启用 App 的 `AnyDeck-AirPlay` 接收端，确认子窗口实际连续出画。
4. 测试竖屏/横屏、断开/重新连接、停止后重新启动；停止后不残留旧画面或监听端口。
5. App 中最近 native 错误经 `anydeck_airplay_copy_last_error` 进入 `[AirPlay] ERROR` 本地日志；独立工具保留 native stderr。不要记录密钥或完整媒体载荷。

## 参考

- [UxPlay 上游固定源码](https://github.com/FDH2/UxPlay/tree/3dbf7ceee65932154e85a2f83963d53520a799fa)
- [legacy pairing 说明](https://github.com/FDH2/UxPlay/wiki/crypto)
- [AirPlay 视频包格式](https://openairplay.github.io/airplay-spec/screen_mirroring/stream_packets.html)
