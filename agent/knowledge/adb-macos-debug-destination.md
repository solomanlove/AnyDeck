# macOS Debug 的 arm64e 目标兼容

## 问题与原因

2026-11-10，本机 Xcode 26.3（17C529）只向 Runner 暴露 `arch:arm64e` 的 My Mac destination。Flutter SDK `d3b14c87690` 的 Debug 构建却按宿主通用架构选择 `platform=macOS,arch=arm64`，在编译前即报目标不存在。单独修改项目 `ARCHS` 无法改变这个 destination 列表。

## 修复

- 项目三个配置通过 `Architecture.xcconfig` 的映射将 `NATIVE_ARCH_64_BIT` 归一为引擎目标：arm64/arm64e → arm64，x86_64 → x86_64；CI 的显式 `ARCHS` 仍可覆盖。仅使用原始 `NATIVE_ARCH_64_BIT` 不足以避免 Release 的 arm64e 泄漏，详见下方后续修复。
- 对本机 Flutter Debug 分支做兼容修复：选择 `generic/platform=macOS`，同时显式传递 `ARCHS=hostArch`。Release 分支保持原样。
- `script/fix_flutter_macos_debug.py` 仅匹配已知源码片段，未知 SDK 拒绝修改。备份源码与原工具 snapshot，然后使用已有 package_config 直接编译工具 snapshot 并原子替换；失败时恢复源码，不覆盖旧 snapshot，不触发 bootstrap/pub upgrade，不改依赖锁或 stamp。

```bash
# 当前机器已应用；新 SDK/新机器遇到同样问题时使用
python3 script/fix_flutter_macos_debug.py --sdk /Users/shijie/development/flutter

# 恢复原 Debug 分支并重新编译工具
python3 script/fix_flutter_macos_debug.py --sdk /Users/shijie/development/flutter --restore

# 仅构建，不启动 App，也不访问设备
flutter build macos --debug --no-pub
```

备份位于 `<SDK>/bin/cache/anydeck_macos_debug_backup/`。此修复会令 SDK 的 `build_macos.dart` 出现有意的本地差异；升级 Flutter 前先恢复，升级后重新确认上游是否已经解决。仓库提交只包含修复工具，不包含 SDK 本身。

## 验证范围

回归覆盖源码变换幂等与恢复、未知版本拒绝、编译失败回滚、保留 SDK 依赖锁与 stamp，以及三个 Xcode 配置在模拟 arm64e/Intel 宿主下的产物架构。显式 arm64/x86_64 Release 与签名权限隔离测试继续保留。

2026-11-10 实测：49 项脚本测试全部通过；未设置架构环境变量的 `flutter build macos --debug --no-pub -v` 成功，日志确认 `-destination generic/platform=macOS` 与 `ARCHS=arm64`。产物 `build/macos/Build/Products/Debug/AnyDeck.app` 的主可执行文件经 `lipo -archs` 确认为 arm64，`codesign --verify --deep --strict` 通过。日志分别保存于 `/tmp/anydeck-debug-fix-tests.log` 与 `/tmp/anydeck-macos-debug-fix-build.log`（临时文件，不保证长期保留）。

不修改 Dart 业务、投屏协议、主题、国际化或设备连接；不自动启动 App。构建成功不等同于 IDE 启动或真机录制验收。

## 后续 Release 架构归一修复（2026-11-10）

用户直接执行 `/bin/bash script/build_macos.sh` 时，Flutter 在 `release_unpack_macos` 报引擎不含 arm64e。前次 Debug 修复显式传入 `ARCHS=arm64`，因此通过构建；Release 未显式覆盖架构，且真实 Xcode arm64e 调用上下文的 `NATIVE_ARCH_64_BIT` 仍可能是 arm64e。旧回归将该值模拟成 arm64，未覆盖这个触发条件。

三个项目配置现在使用 `$(ANYDECK_ARCH_$(NATIVE_ARCH_64_BIT))`，映射由 Debug/Release 共用的 `Architecture.xcconfig` 提供（Profile 复用 Release）。回归直接把 `NATIVE_ARCH_64_BIT` 设置成 arm64e、arm64、x86_64，检查三个配置输出，并保留显式两种架构的覆盖测试。

打包脚本同时将选定架构写入 `ANYDECK_TARGET_ARCH` 和 `FLUTTER_XCODE_ARCHS`，保证 Pods、Rust、Flutter 选择一致。优先级为 `ANYDECK_TARGET_ARCH` → `FLUTTER_XCODE_ARCHS` → `uname -m`；arm64e 归一为 arm64，仅接受单个 arm64/x86_64，未知或多架构值在构建和复制前拒绝。原输出目录参数与 ad-hoc 签名处理保持不变。

```bash
# 默认当前宿主，无需额外架构参数；可从任意工作目录执行
/bin/bash /Users/shijie/Documents/AdbManage/script/build_macos.sh
```

依赖有新版、Swift Package Manager 支持和 `SWIFT_DEBUG_INFORMATION_*` 的 Warning 并非本次失败原因；本次不升级依赖或迁移插件。

实测交付：从 `script/` 目录原样执行用户的绝对路径命令，不预设架构环境变量，完整 Release 构建与两次整包签名/复制成功，产物为 `Products/AnyDeck.app`。`verify_macos_release.py --arch arm64` 检查 35 个 Mach-O 的架构、ad-hoc 签名及依赖通过，主程序 lipo 为 arm64，`codesign --verify --deep --strict` 通过；52 项脚本测试全部通过。日志为 `/tmp/anydeck-release-arm64e-fix-build.log` 与 `/tmp/anydeck-release-arm64e-fix-tests.log`。未启动 App，Intel 为配置/脚本回归，未在本机交叉编译或运行 Intel 包。
