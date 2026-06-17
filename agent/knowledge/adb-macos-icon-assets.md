# macOS 图标资源机制

## 概述

本文档记录 AdbManage macOS 端 Dock 图标、Flutter 内部 App logo、以及右上角菜单栏图标的资源边界。三类图标可以使用同一个视觉来源，但输出文件和使用场景必须分开，避免菜单栏使用带背景的大尺寸 App icon 后在 macOS dark mode / light mode 下显示不清晰。

## 资源分工

| 场景 | 文件 | 用途 |
| --- | --- | --- |
| Flutter App logo | `assets/brand/app_logo.png` | Dashboard、侧边栏等 Flutter UI 内展示 |
| Dock 图标 | `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png` | macOS App bundle 的 Dock / Finder 图标 |
| 菜单栏图标 | `assets/brand/app_tray_icon.png` | `tray_manager` 在 macOS 右上角菜单栏显示 |
| 菜单栏源文件 | `assets/brand/app_tray_icon.svg` | 从 `app_logo.svg` 抽取手机主体后的透明背景纯色图形 |

## 实现约定

1. `assets/brand/app_logo.svg` 是主视觉源文件，包含背景、装饰线、手机主体和终端符号。
2. `app_logo.png` 和 `AppIcon.appiconset` 使用满画布背景，不能保留透明外圈，避免 Dock / Finder 预览出现白边。
3. `app_tray_icon.png` 使用手机线框和终端符号的 template icon，必须是透明背景单色 stroke 图形，不能做成实心 silhouette，否则 macOS 菜单栏会渲染成白色方块。
4. macOS 托盘初始化时使用：

```dart
trayManager.setIcon(AppIcons.appTrayIcon, isTemplate: Platform.isMacOS)
```

`isTemplate: true` 让 AppKit 按系统菜单栏状态自动渲染图标颜色，避免浅色/深色模式下可读性问题。

## 生成命令

使用 macOS 自带轻量工具即可完成 SVG 到 PNG 的转换和缩放：

```bash
qlmanage -t -s 1024 -o /tmp/adbmanage_icon_gen assets/brand/app_logo.svg
sips -z 64 64 /tmp/adbmanage_icon_gen/app_tray_icon.svg.png --out assets/brand/app_tray_icon.png
```

生成 Dock 图标时需要同步输出 `16, 32, 64, 128, 256, 512, 1024` 七个尺寸，并保持 `Contents.json` 的文件名映射不变。
