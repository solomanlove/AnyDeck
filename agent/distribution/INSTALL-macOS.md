# AnyDeck macOS 安装说明

分别提供 Apple Silicon（M1 或更新，arm64）与 Intel（x86_64）安装包，最低部署目标为 macOS 12。请按“关于本机”显示的芯片或处理器选择对应版本。

## 安装

1. Apple Silicon 下载 `AnyDeck-macOS-arm64.dmg`，Intel 下载 `AnyDeck-macOS-x86_64.dmg`；打开后将 AnyDeck 拖到 Applications。
2. 也可以下载 ZIP，解压后将 `AnyDeck.app` 拖到“应用程序”。
3. 此版本使用免费 ad-hoc 签名，未经 Apple 公证。首次打开如提示无法验证开发者，在确认下载来自本仓库后，进入“系统设置 → 隐私与安全性 → 仍要打开”并确认。
4. 如公司管理策略禁止打开此类 App，请联系管理员。不要关闭系统整体安全保护。

## 设备工具

App 已包含投屏服务端、Rust 引擎、APK 分析器及 Share Core。设备连接仍需本机 CLI：

```bash
brew install android-platform-tools
```

内嵌投屏使用 App 自带的投屏服务端和 Rust 引擎，无需在电脑上另外安装 scrcpy。仅在使用“电脑本地录制”等外部 scrcpy 录制模式时，才需要按需安装该 CLI。

HarmonyOS 设备需要 HDC（可在 AnyDeck 设置中指定路径）；iOS 设备需要 go-ios。手机端需按帮助中心开启对应调试权限。

## 功能边界

- macOS 虚拟摄像头扩展需要正式开发者签名及系统批准；此 ad-hoc 版本不提供可激活的系统虚拟摄像头。
- 屏幕投屏、手机摄像头预览与系统虚拟摄像头属于不同功能。
- 发布包签名与组件校验不代替各设备型号的真机兼容性验收。

## 校验下载

`SHA256SUMS` 包含两种架构的 DMG、ZIP 和本说明；只下载其中一种架构时，可仅核对已下载文件：

```bash
shasum -a 256 -c SHA256SUMS --ignore-missing
```

问题反馈：https://github.com/solomanlove/AnyDeck/issues
