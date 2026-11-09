# GitHub macOS ad-hoc 自动发布

## 需求与范围

通过 GitHub Actions 构建当前 AnyDeck，使用免费 ad-hoc 签名，发布可下载的 DMG、ZIP、SHA-256 与安装说明。当前 Runner/Xcode 和私有 Share Core 均锁定 arm64，因此仅发布 Apple Silicon 版本。官网截图替换已按用户要求暂停，等待设备上线后另行通知。

## 发布入口

- Workflow：`.github/workflows/release-macos.yml`。
- 固定 Flutter 3.47.2；macOS 15 arm64 Runner 安装 OpenSSL、libplist、pkg-config 及 Rust target。
- 测试前先执行 `flutter build macos --release --config-only --no-pub` 生成干净 Runner 必需的 Flutter/Xcode 配置。
- `script/build_macos.sh` 复用 Xcode 原生构建阶段及现有 ad-hoc 签名策略。
- `script/package_macos_release.sh` 调用验证器后生成 DMG、保留权限与符号链接的 ZIP、`SHA256SUMS` 与 `INSTALL-macOS.md`。
- 安装说明源文件：`agent/distribution/INSTALL-macOS.md`。

手动运行 Actions 的 `macOS Release` 只构建与上传 Artifact；推送与 App 版本相同的 Tag 自动创建公开 Release：

```bash
git tag v1.0.0
git push origin v1.0.0
```

版本读取构建后 Info.plist，Tag 必须等于 `v<CFBundleShortVersionString>`。先更新 `pubspec.yaml` 再发布新版本。已有 Release 不自动覆盖，避免相同版本下悄悄替换安装包。

## 一次性私有组件配置

默认 `GITHUB_TOKEN` 不能读取另一私有仓库。需要在 `AnyDeck-Share-Core` 配置专用 **只读 Deploy key**，将其私钥作为主仓库的 Actions Secret `SHARE_CORE_DEPLOY_KEY` 保存。不要使用个人主 SSH 私钥，也不要打开 Deploy key 的写权限。

1. 生成仅用于此 CI 的 Ed25519 key。
2. `AnyDeck-Share-Core → Settings → Deploy keys` 添加公钥，保持只读。
3. `AnyDeck → Settings → Secrets and variables → Actions` 添加 `SHARE_CORE_DEPLOY_KEY`，内容为该私钥。
4. 手动运行 Workflow，构建通过后再推送版本 Tag。

Workflow 在临时 SSH agent 中加载 key，通过 GitHub HTTPS metadata 取得 SSH host keys；结束获取步骤即销毁 agent。只提取锁文件指定 commit 下的制品，校验 SHA-256 后存入构建缓存。后续编译阶段不持有私有仓库凭据。缺少 Secret 时会在下载 SDK 和编译之前明确失败。

## 验证门禁

```bash
python3 -m unittest discover -s test/script -v
./script/build_macos.sh
./script/package_macos_release.sh Products/AnyDeck.app build/release
```

- 检查 ad-hoc 签名与嵌套签名、arm64 架构、Rust 动态库/APK helper/Share Core 完整性。
- 检查实际链接的动态库，禁止开发机绝对依赖，要求 Frameworks 和 helper 相对依赖随包提供。Flutter 引擎未使用的默认 RPATH 不等于实际依赖，不单独拒绝。
- 真实最小 Mach-O fixture 覆盖版本不匹配、缺组件、签名篡改、Homebrew 绝对依赖和 ZIP/DMG 校验；归档解压后再次校验签名、执行权限与符号链接。
- 构建 job 只有主仓库只读权限，独立发布 job 才持有 `contents: write`，且不加载私有组件 key。

## 本地验证记录（2026-11-09）

- 37 项脚本回归通过；随后针对 fixture 与 CI Tag 隔离的修正，6 项发布回归再次通过。
- 完整 macOS Release 构建通过，35 个 Mach-O 文件通过签名、架构及实际依赖检查。
- 已生成约 55 MB DMG 与 50 MB ZIP，SHA-256 清单校验通过，DMG 镜像校验通过。
- Workflow 通过 actionlint（含 ShellCheck）验证。
- GitHub 云端构建与实际 Release 上传尚需配置专用只读凭据后验证；不能用本地构建成功替代云端验收。

## 分发边界与回归

本通道没有 Developer ID、公证或摄像头扩展的正式 provisioning。用户首次启动可能需要在系统隐私与安全性中手动允许。虚拟摄像头不能按普通 ad-hoc 包激活；ADB/HDC/go-ios 等设备 CLI 仍按安装说明配置。

不修改 Dart UI、投屏链路、Isolate 通信、主题或国际化。脚本与包验证不证明其他 Mac 的真实启动、USB/无线设备连接和 Camera Extension 激活已验收。首发后应在另一台 Apple Silicon Mac 从浏览器下载安装，并验证主窗口、APK 分析、设备连接和投屏。

回退 workflow 可 revert 对应 commit；回退公开版本应发布新版本或在 GitHub Releases 撤回问题版本，不覆盖既有二进制附件。
