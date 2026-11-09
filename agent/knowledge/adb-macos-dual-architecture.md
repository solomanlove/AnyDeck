# macOS arm64 与 Intel 分架构发布

## 需求与交付

从 v1.0.1 起分别构建 Apple Silicon（arm64）与 Intel（x86_64）安装包，保持 ad-hoc 签名。两个架构全部验证成功才创建 Release，官网在 Release 确认可下载后更新对应入口；不替换截图。

## 构建链路

- Xcode 的三个项目配置默认使用 `$(NATIVE_ARCH_ACTUAL)`，不再固定 arm64。CocoaPods 默认跟随宿主，也接受 `ANYDECK_TARGET_ARCH`。
- Actions matrix 在 `macos-15` 和 `macos-15-intel` 分别构建。设置 `FLUTTER_XCODE_ARCHS` 显式传递单一架构，关闭 SDK 的 arm64-only feature flag，避免 Intel Release 被覆盖成 arm64。
- Rust bridge 与 APK helper 使用既有 aarch64/x86_64 target 路由；每个 Runner 使用本架构的 OpenSSL/libplist。
- Share Core 私有仓库构建 Intel 制品，检查所有 helper 和 OpenSSL 的 x86_64 slice、签名，执行 IPC hello 与真实双向 loopback 互传。主仓库只读取固定 commit 下的两个 ZIP，分别校验 SHA-256。
- `script/package_macos_release.sh <App> <output> [arm64|x86_64]` 默认采用宿主架构，生成对应名称的 DMG、ZIP、通用安装说明与校验清单。
- 发布 job 分别下载两个 Artifact，先检查安装说明一致，再合并校验清单并验证四个安装包。使用新 Tag 创建新 Release，不覆盖 v1.0.0。

## 验证与边界

`verify_macos_release.py --arch` 检查 Share Core manifest 架构、包内全部 Mach-O 的目标 slice、ad-hoc/嵌套签名与依赖完整性。`smoke_macos_release.py` 必须在匹配的原生宿主上执行，真实启动随包 Core IPC hello 与 APK helper 分析内置测试 APK；CI 的 `--launch-app` 额外验证 App 进程启动后存活 8 秒并回收进程，不访问手机。这是启动存活检查，不证明窗口视觉或设备功能已验收。

当前 40 项本地脚本回归通过，包含错误架构标记拦截、符号链接与执行权限保留、两个 Xcode target 的两种架构设置及签名权限隔离；新增 Intel manifest 安装回归也已通过。CI 对应架构将再次执行完整测试。

私有 Intel 制品锁定至 `0de9b2e71479b373d0eed96c0783dd089c8a8e15`；[原生 CI](https://github.com/solomanlove/AnyDeck-Share-Core/actions/runs/42629522946) 已通过 40 项 Swift、Rust 离线与 integration 回归及两份真实 Core 双向文件互传。arm64 ZIP 内容保持原锁定制品不变。

私有 Core 原有物理广播测试在 Hosted Runner 缺少 LAN 路由，出现 `HostUnreachable (65)`；Intel 制品流程显式过滤这一个环境用例，保留其余离线/loopback 回归。Intel 手机无线投屏、蓝牙、旧 macOS 版本及 Camera Extension 激活仍需真实设备验收，不能由编译和 helper 检查推导完成。

本次不改 Dart 业务、投屏协议、Isolate、主题或可见文案；原有摄像头正式签名与本地 ad-hoc 权限隔离继续有效。

## 维护

```bash
python3 -m unittest discover -s test/script -v
actionlint .github/workflows/release-macos.yml
git tag v1.0.1
git push origin v1.0.1
```

修复必须先通过手动 Workflow 验证，再创建新版本 Tag。两个架构任意一个失败时不会执行发布 job。

## 首轮双架构 CI 证据

[手动验证 42630601956](https://github.com/solomanlove/AnyDeck/actions/runs/42630601956) 的 arm64 与 x86_64 job 均成功，各执行 40 项打包回归。各自的 35 个 Mach-O 架构与 ad-hoc 签名检查、DMG/ZIP 校验、Core IPC、真实 APK 分析及 App 进程存活 8 秒全部通过。验证的 App commit 为 `af58879c2a0b19a938df5371f24ea5ee55cdfb6e`，对应 v1.0.1 Tag。

Tag 首轮 arm64 在获取 `api.github.com/meta` 时遇到 HTTP 403，尚未进入编译；Intel 未受影响。后续 workflow 改用该 job 的短期 `github.token` 获取公开主机公钥，避免匿名 API 配额耗尽；只读私有 Deploy key 的权限与使用方式不变，未放宽 SSH 主机身份检查。

## 已验证产物的发布恢复

`.github/workflows/publish-macos-verified.yml` 接受目标 Tag 与完整成功的来源 run ID。仅允许同仓库 macOS Release Workflow 的 push/workflow_dispatch 事件，且来源 commit 必须与 Tag 完全一致；失败、未完成、PR 或不同 commit 均拒绝。恢复流程重新下载两个 Artifact、验证 SHA-256、解压并校验所有 Mach-O/签名/依赖，额外执行 Intel helper 与启动检查，再合并四个包发布，仍不覆盖已有 Release。来源策略有正反向单元测试。

这是 Runner 排队或网络错误后的恢复入口，不改变 Tag 的代码或降低原生构建与 smoke 门禁。正常 Tag 自动发布流程保持原样。
