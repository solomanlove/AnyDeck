# AnyDeck

AnyDeck 是一个轻量级 Flutter Desktop 工具箱，面向 Android 开发和 QA 调试流程。

## 作者信息

| 项目 | 内容 |
|---|---|
| 定位 | Android 开发调试工具维护者 |
| 软件方向 | 聚焦 ADB、scrcpy 和 Android QA 调试流程的轻量桌面工具 |

## 软件说明书

### 软件定位

AnyDeck 基于 Flutter Desktop 构建，把常用 Android 调试能力集中到一个桌面端工具中，适合开发、自测、QA 排查和设备状态检查。

### 使用前准备

| 依赖 | 说明 |
|---|---|
| `adb` | 必需，用于设备发现、Shell、应用管理、文件传输和日志读取 |
| `scrcpy` | 可选，用于外部投屏 |
| Android 设备 | USB 调试或无线调试需要在手机端开启开发者选项 |

### 基础使用流程

1. 通过 USB 连接设备，或使用 TCP/IP、二维码、配对码完成无线连接。
2. 在设备列表中选择目标设备。
3. 按需进入概览、控制、应用、文件、Logcat、终端或 `scrcpy` 功能面板。
4. 执行清除数据、卸载、冻结、重启等影响设备状态的操作前，先确认目标设备和包名。

首版实现遵循 `FLUTTER_ADB_DESKTOP_TECH_PLAN.md`：

```text
Flutter Desktop UI
  -> Dart Process 调用 adb
  -> Dart Process 启动外部 scrcpy
  -> Riverpod 管理设备、会话和长生命周期进程
```

## 当前范围

| 模块 | 状态 | 说明 |
|---|---:|---|
| 设备列表 | ✅ 已实现 | 轮询 `adb devices -l`，自动去重、型号/序列号展示、批量删除 |
| TCP/IP 连接 | ✅ 已实现 | `adb connect`、二维码配对、配对码配对 |
| ADB 服务管理 | ✅ 已实现 | 一键重启 ADB 服务端 |
| scrcpy 启动器 | ✅ 已实现 | 使用默认 MVP 参数启动外部 `scrcpy` |
| 设备操作 | ✅ 已实现 | 文本输入、Home/Back/Power/Menu 键、音量、Wi-Fi、通知栏、屏幕旋转、当前焦点查询 |
| 设备信息 | ✅ 已实现 | 硬件概览含逻辑密度和刷新率，支持本地持久化缓存 |
| 布局辅助 | ✅ 已实现 | 布局边界、深色/浅色模式、Layout Inspector XML 树与截图预览 |
| 应用管理 | ✅ 已实现 | 安装 APK、应用列表（拼音搜索）、启动、强停、清数据、冻结/解冻、卸载、详情查看、APK 导出 |
| 进程管理 | ✅ 已实现 | 获取设备进程列表（PID/CPU/CPU 时间/用户）、支持仅显示应用、搜索与杀死进程 |
| 网页调试 | ✅ 已实现 | 扫描并列出运行中的 Web/WebView 页面、支持在浏览器中打开或调试网页 |
| 文件管理 | ✅ 已实现 | 浏览 `/sdcard/`、拖拽上传、下载、删除 |
| Logcat | ✅ 已实现 | 启停日志流、保留最近 1000 行、关键字筛选 |
| 终端调试 | ✅ 已实现 | 多标签 ADB Shell、命令历史、常用命令收藏与重置 |
| 模拟器管理 | ✅ 已实现 | AVD 列表扫描、启动/停止模拟器、运行状态监控、紧凑布局折叠展示 |
| 品牌资源 | ✅ 已实现 | 应用内 Logo、macOS AppIcon、Windows ICO 图标生成与更新 |

拖拽行为：

| 拖入文件 | 动作 |
|---|---|
| `.apk` | `adb install -r <apk>` |
| 其他文件 | `adb push <file> <current remote path>` |

## 项目结构

```text
lib/
  app/
    l10n/              # 中文本地化字符串
    router/
    theme/
  core/
    adb/               # ADB 服务封装
    apps/              # 应用管理服务
    device_actions/    # 设备操作（按键、旋转、通知栏等）
    device_info/       # 设备信息采集与持久化
    emulator/          # Android 模拟器管理服务
    files/             # 文件管理服务
    logcat/            # Logcat 日志服务
    process/           # 进程管理服务
    providers/         # Riverpod 全局状态管理
    scrcpy/            # scrcpy 投屏服务
    terminal/          # ADB 终端会话管理
    web_debug/         # Web 与 WebView 调试服务
  features/
    dashboard/
      presentation/    # 主界面展现层入口 (dashboard_screen.dart)
        apps/          # 应用管理模块
        control/       # 控制中心模块
        devices/       # 设备发现、连接、配对与模拟器
        files/         # 手机文件管理器
        layout/        # 界面布局分析 (Layout Inspector)
        logcat/        # Logcat 日志查看器
        overview/      # 主界面外壳与概览页
        processes/     # 进程管理器
        screenshot/    # 屏幕截图与录制
        terminal/      # 交互式终端 (ADB Shell)
        webpages/      # 手机网页调试
        widgets/       # 公共对话框与通用组件
assets/
  brand/               # 应用 Logo 品牌资源
tool/
  generate_app_icons.swift
test/
  adb_service_test.dart
  web_debug_test.dart
```

## 本地依赖

| 工具/依赖 | 推荐版本 | 用途 | 官方链接 |
|---|---|---|---|
| `adb` | - | 设备发现、应用管理及 shell 命令调试 | [Android SDK Platform Tools](https://developer.android.com/tools/releases/platform-tools) |
| `scrcpy` | `v4.0` | 内嵌投屏与外部投屏核心依赖，推送到手机端的 `scrcpy-server` | [Genymobile/scrcpy](https://github.com/Genymobile/scrcpy) |
| `FFmpeg` | `v6.0+` | 供原生 C++ 编解码插件 `scrcpy_flutter` 动态链接并进行视频流硬解 | [FFmpeg](https://ffmpeg.org) |
| Flutter Desktop | - | 编译构建 macOS、Windows、Linux 桌面目标应用 | [Flutter](https://flutter.dev) |


## 构建release包
```flutter build macos```，执行该命令后，生成的 release 应用（.app文件）位于项目目录下的 build/macos/Build/Products/Release/

后续分发：如果你需要将应用分发给用户（尤其是通过非 Mac App Store 渠道分发），还需要对应用进行公证（notarization）。通常需要先在 Xcode 中打开项目：```open macos/Runner.xcworkspace```
然后在 Xcode 中完成签名、公证等分发准备工作。

环境要求：确保已安装 Xcode 并配置好命令行工具。

配置 Xcode 命令行工具（如尚未配置）
```sudo sh -c 'xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -runFirstLaunch'```