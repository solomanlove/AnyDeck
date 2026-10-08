# iOS AirPlay Server：当前实现、连接故障与验收边界

## 当前结论（2026-10-08）

**该实现仍是实验性接收端，尚不能完成真实 iPhone 的加密屏幕镜像。**
Bonjour 可发现、RTSP 返回成功和模拟客户端自测通过，都不能证明视频解密或真机出画可用。此前本文中的“协议完整实现”“100% 商业合规”“全套验证通过”等结论没有对应真机/来源审计证据，已撤销。

本次输入是 iPhone 提示“无法连接 AnyDeck-AirPlay”的截图。没有取得该次连接的 RTSP 抓包或 native stderr，因此以下为代码确认的协议缺陷，不能断言截图对应的首次断点。

## 已确认缺陷与修复

| 环节 | 原实现问题 | 本次处理 |
| --- | --- | --- |
| `/info` | 带 qualifier 时只返回 TXT；能力位与 Bonjour 不一致，statusFlags 也不一致 | qualifier 请求也返回身份、公钥和能力；共享 features/statusFlags 常量，移除未实现音频/云播放等能力声明 |
| `pair-setup` | 32 字节请求只返回空 body | 返回服务端 32 字节 Ed25519 公钥，拒绝错误长度 |
| `pair-verify` 第一阶段 | legacy 报文错误使用 ChaCha20-Poly1305，返回 112 字节 | 改用 X25519 + Ed25519 + AES-128-CTR，返回 96 字节 |
| `pair-verify` 第二阶段 | 根据长度 >=36 误判为第一阶段，且空包可假成功 | 根据 4 字节 flag 区分；两阶段均严格 68 字节；延续 CTR 第 64 字节位置校验客户端签名，失败/重放拒绝 |
| 会话隔离 | 所有 TCP 客户端共享一个 Crypto 状态 | 每个 RTSP 连接独立上下文，最多 16 个客户端 |
| `SETUP` | 忽略 ekey/eiv/streams，返回未监听的零 timing/event 端口并进入 Mirroring | 配对后返回明确 501 与缺失能力原因，未配对返回 403；RECORD 在无媒体会话时返回 455，不伪造投屏成功 |
| 视频解析 | 128 字节头错误使用大端；type 1 avcC 当作普通 AVCC；超大帧跳过后丢失包边界 | 小端头；区分 codec/video/heartbeat；严格参数集及 NAL 长度；超大包断开 |
| 停止与重启 | 父任务结束后子监听继续运行，abort 无法释放端口 | `tokio::join!` 持有监听 future，`JoinSet` 管理子连接；停止释放监听和空闲连接 |
| 端口冲突 | 自动修改系统 AirPlay 偏好，killall ControlCenter/cfprefsd | 仅选择后续空闲端口，Bonjour 广播实际端口 |
| 诊断 | Rust stderr 没有进入 Dart 本地日志；错误可能无响应 | 有界错误缓冲 + 可选 FFI 符号 + Dart 去重记录；解析、握手、SETUP 错误返回真实 RTSP 状态码 |
| 模拟器 | 与服务端使用同一种错误加密方式、空第二阶段；未发送视频却宣称全流程通过 | 改为显式端口的只读探针；独立协议客户端放入 Rust 测试，明确不代表真机出画 |

## 模块职责

- `rust/device_bridge/src/airplay/bonjour.rs`：DNS-SD 广播与统一能力常量。
- `crypto.rs`：legacy 两阶段配对；使用 RustCrypto `ctr 0.9`，不再用配对派生值冒充视频密钥。
- `rtsp.rs`：有界 RTSP 解析、身份/能力响应、配对路由与明确失败响应。
- `packet.rs`：小端视频头、avcC SPS/PPS、AVCC NAL 解析。
- `mod.rs`：监听任务、连接隔离、资源回收与最新错误缓冲。
- `tests.rs`：独立客户端、协议样本、异常输入与 loopback 连接回收回归。
- `rust/device_bridge/src/c_api_airplay.rs`：FFI；新增 `anydeck_airplay_copy_last_error`，复制 UTF-8 错误到调用方缓冲。
- `lib/core/airplay/airplay_server_service.dart`：300ms 状态轮询中读取并去重输出错误，由已有日志系统采集；旧 dylib 缺少新符号时保持兼容。

不修改 Android/scrcpy、iOS USB 或 WDA 链路；没有增加 UI、主题或本地化文案。

## 真实投屏仍缺少的部分

1. `/fp-setup` 的固定响应模板仅构成握手应答，**不等于 FairPlay key unwrap**。必须结合会话握手数据处理 `SETUP.ekey`，得到媒体密钥；随后按 streamConnectionID 和会话材料派生持续的 AES-CTR 视频流上下文。现有接收链路没有这些能力。
2. 分阶段解析媒体 SETUP、实际 event TCP / timing UDP 通道、时钟同步和流关闭；需要匹配客户端版本。不能返回零端口假装成功。
3. 流必须关联已验证的客户端与协商会话，首个有效解码帧才应驱动 Mirroring 状态。目前拒绝未经媒体 SETUP 的视频连接。
4. 当前沿用源码固定身份种子和固定 pi；正式发布前需改为每安装实例生成、持久化的身份，并验证升级/重新配对行为。
5. 跨 RTSP 连接的会话恢复、Bonjour 注册异步结果处理、客户端型号/系统矩阵、声音、真实视频与 Flutter Texture 链路仍需独立实现或验收。

用户说明未来用于商业化。本次未引入 GPL/LGPL 媒体解包组件，也未启动外部接收端。商业化并不自动等于禁止所有此类依赖，但在没有明确集成与分发方案前，不能声称其授权满足项目目标。后续应选择来源和授权已核验的接收端 SDK/实现，或推进独立协议研发。现有 FairPlay 固定模板的来源也需核验，不能因 Cargo 依赖采用宽松许可证就作整体商业合规保证。

## 验证命令与边界

```bash
cargo test --manifest-path rust/device_bridge/Cargo.toml --lib
cargo check --manifest-path rust/device_bridge/Cargo.toml --examples
flutter analyze --no-pub lib/core/airplay test/airplay_server_service_test.dart
flutter test --no-pub test/airplay_server_service_test.dart
```

2026-10-08 执行结果：Rust 30 passed / 1 ignored（其中 AirPlay 11 passed）；examples 编译检查通过；Dart analyze 无问题，2 项状态模型测试通过。Dart 测试不覆盖真实 FFI 动态库与 Texture。

自动测试覆盖：96 字节服务端证明、真实 68 字节客户端第二阶段签名、错误签名/重放/零 ECDH、交错客户端、qualifier 身份/能力、缺失 FairPlay 的 SETUP 明确失败、RTSP 分片/粘包/异常长度、非法 FairPlay mode、小端头、avcC/AVCC 边界、停止后空闲 TCP 关闭与端口释放。

本次未启动桌面 App、未启动 Bonjour 真机监听，也未重新打包或替换正在运行的 dylib。修改后的 Rust 库需经项目原有构建流程重新构建，运行中的旧进程不会自动使用修复。

待后续完整媒体实现后，真机验收须依次确认：发现 → 两阶段配对 → FairPlay 密钥解包 → event/timing/视频 SETUP → 首帧解码 → Texture 出画 → 横竖屏 → 断开/重连/停止后端口回收。不得把前一阶段成功当成整个链路通过。

## 协议参考

- [legacy pairing 交互说明](https://github.com/FDH2/UxPlay/wiki/crypto)：作为线协议核对，未引入该项目实现代码。
- [AirPlay 视频包格式](https://openairplay.github.io/airplay-spec/screen_mirroring/stream_packets.html)：小端视频头与 avcC 配置记录。
- [AirPlay 能力位](https://openairplay.github.io/airplay-spec/features.html)：Bonjour 与 `/info` 统一使用的位语义。
