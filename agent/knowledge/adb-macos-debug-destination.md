# macOS Debug 的 arm64e 目标兼容

## 问题与原因

2026-11-10，本机 Xcode 26.3（17C529）只向 Runner 暴露 `arch:arm64e` 的 My Mac destination。Flutter SDK `d3b14c87690` 的 Debug 构建却按宿主通用架构选择 `platform=macOS,arch=arm64`，在编译前即报目标不存在。单独修改项目 `ARCHS` 无法改变这个 destination 列表。

## 修复

- 项目三个配置默认使用 `$(NATIVE_ARCH_64_BIT)`，避免 `NATIVE_ARCH_ACTUAL` 的宿主子架构泄漏；Intel 默认仍为 x86_64，CI 的显式 `ARCHS` 仍可覆盖。
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
