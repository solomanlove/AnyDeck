# AnyDeck macOS 安装说明

此版本面向 Apple Silicon（M1 或更新）Mac，最低 macOS 12。Intel Mac 不适用。

## 安装

1. 下载 `AnyDeck-macOS-arm64.dmg`，打开后将 AnyDeck 拖到 Applications。
2. 也可以下载 ZIP，解压后将 `AnyDeck.app` 拖到“应用程序”。
3. 此版本使用免费 ad-hoc 签名，未经 Apple 公证。首次打开如提示无法验证开发者，在确认下载来自本仓库后，进入“系统设置 → 隐私与安全性 → 仍要打开”并确认。
4. 如公司管理策略禁止打开此类 App，请联系管理员。不要关闭系统整体安全保护。

## 设备工具

App 已包含投屏服务端、Rust 引擎、APK 分析器及 Share Core。设备连接仍需本机 CLI：

```bash
brew install android-platform-tools scrcpy
```

HarmonyOS 设备需要 HDC（可在 AnyDeck 设置中指定路径）；iOS 设备需要 go-ios。手机端需按帮助中心开启对应调试权限。

## 功能边界

- macOS 虚拟摄像头扩展需要正式开发者签名及系统批准；此 ad-hoc 版本不提供可激活的系统虚拟摄像头。
- 屏幕投屏、手机摄像头预览与系统虚拟摄像头属于不同功能。
- 发布包签名与组件校验不代替各设备型号的真机兼容性验收。

## 校验下载

将 `SHA256SUMS`、DMG、ZIP 和本说明下载到同一目录后运行：

```bash
shasum -a 256 -c SHA256SUMS
```

问题反馈：https://github.com/solomanlove/AnyDeck/issues
