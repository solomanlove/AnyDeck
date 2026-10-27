# UxPlay 协议核心来源

- 上游：https://github.com/FDH2/UxPlay
- 固定 commit：`3dbf7ceee65932154e85a2f83963d53520a799fa`（1.74 experimental）。
- 2026-10-09 核对：现有 vendor/lib 文件与该 commit 逐文件一致，只有下述本地补丁。
- 范围：`lib/` 协议、FairPlay、llhttp 与 Bonjour 后端；未接入 GStreamer renderer。
- 保留上游根目录 LICENSE 与各文件版权、许可头。本实验接入不表示商业分发授权已完成核验。

## 本地补丁

- `lib/raop.c`：`raop_stop_httpd` 判断 httpd 是否为空，允许 init2 失败路径安全析构。
- `lib/dnssd.*`、`lib/dns_sd/dns_sd.c`：允许接入层指定 Bonjour interface，避免服务同时发布到 USB link-local 链路。
- `native/uxplay_bridge.c` 位于 vendor 目录外，是 AnyDeck 生命周期、能力声明和媒体回调适配层。

- 2026-10-27 `http_handlers.h` / `raop.c`：HTTP 视频结束和错误回调使用正确的连接/全局上下文；直连 HTTP(S) 媒体不依赖 FCUP UUID 缓存，补充 plist、Session ID/UUID、查询参数校验与 URL 日志脱敏。
- 2026-10-27 `raop_handlers.h`：开始镜像视频时停止当前 HTTP 媒体；不销毁独立 DLNA 播放器。Video/HLS 能力和媒体回调在 vendor 外的 native bridge 中同时开启。

- 2026-10-28 `httpd.c`：PTTH 升级连接新建 request 时调用 `set_reverse` 而非误调用 getter，防止 iOS 的 EVENT/HTTP 应答被解析为请求并断开；真实 TCP 回归覆盖分段与连续应答。

## 构建

macOS 安装 `brew install pkgconf openssl@3 libplist`。Cargo 默认启用 `airplay-uxplay`，静态链接 libcrypto/libplist；DNS-SD 使用系统 Bonjour。`--no-default-features` 仅保留旧 Rust 协议回归，不能提供完整加密镜像。
