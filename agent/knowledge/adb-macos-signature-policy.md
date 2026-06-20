# macOS 签名与 system policy 修复机制

## 背景

本项目 macOS Debug / Release 产物会加载 `FlutterMacOS.framework`、Pod frameworks 以及 scrcpy 相关 `.dylib`。如果 `.app` 或内部 framework 带有 `com.apple.provenance` / `com.apple.quarantine` 扩展属性，macOS 可能在 dyld 阶段拒绝加载本地 adhoc 签名 framework，表现为：

```text
Library not loaded: @rpath/FlutterMacOS.framework/Versions/A/FlutterMacOS
code signature ... not valid for use in process: library load denied by system policy
```

这种问题不是 Flutter 业务代码错误，优先检查构建产物和 Flutter SDK cache 的签名与扩展属性。

## 排查命令

```bash
codesign --verify --deep --strict --verbose=4 build/macos/Build/Products/Debug/AnyDeck.app
codesign --verify --strict --verbose=4 build/macos/Build/Products/Debug/AnyDeck.app/Contents/Frameworks/FlutterMacOS.framework
xattr -lr build/macos/Build/Products/Debug/AnyDeck.app | rg 'provenance|quarantine'
```

如果 Flutter SDK cache 自身异常，可进一步检查：

```bash
codesign --verify --strict --verbose=4 \
  $FLUTTER_ROOT/bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework/macos-arm64_x86_64/FlutterMacOS.framework
xattr -lr $FLUTTER_ROOT/bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework | rg 'provenance|quarantine'
```

## 自动修复入口

仓库脚本：

```bash
./script/fix_macos_app_policy.sh build/macos/Build/Products/Debug/AnyDeck.app
```

脚本行为：

1. 清理 `.app` 内部的 `com.apple.provenance`。
2. 清理 `.app` 内部的 `com.apple.quarantine`。
3. 对 `.app` 执行本地 adhoc deep sign：

```bash
codesign --force --deep --sign - "$APP_PATH"
```

## 构建集成

1. `script/build_macos.sh` 在 Release app 复制前后都会调用 `fix_macos_app_policy.sh`，避免分发到 `Products/` 后重新携带异常扩展属性。
2. Debug 调试不要直接使用普通 `flutter run -d macos` 复现该环境问题；使用：

```bash
./script/run_macos_debug.sh
```

该脚本会先执行 `flutter build macos --debug`，再清理 `AnyDeck.app` 的 system policy 属性，最后通过 `flutter run -d macos --debug --no-build` 启动已修复的构建产物。

## 边界

- 该脚本只处理本地调试和本地分发的 adhoc 签名产物，不替代正式 Developer ID 签名、公证或 App Store 签名。
- Xcode target build phase 不足以兜底该问题；在部分环境中，最终 `.app` 会在 build phase 后再次获得 `com.apple.provenance`。
- 如果 Flutter SDK cache 中的 `FlutterMacOS.xcframework` 本身验签失败，需要先清理 SDK cache 的 provenance/quarantine，并对本地 cache 重新 adhoc 签名，或重新执行 Flutter engine precache。
