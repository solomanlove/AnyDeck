# AdbManage

AdbManage 是一个轻量级 Flutter Desktop 工具箱，面向 Android 开发和 QA 调试流程。

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
| 设备列表 | 初版 | 通过 `AdbService` 轮询 `adb devices -l` |
| TCP/IP 连接 | 初版 | 调用 `adb connect <ip>:<port>` |
| scrcpy 启动器 | 初版 | 使用默认 MVP 参数启动外部 `scrcpy` |
| 设备操作 | 初版 | 文本输入、Home/Back/Power、音量、Wi-Fi 开关 |
| 布局辅助 | 初版 | 布局边界、深色/浅色模式 |
| 应用管理 | 初版 | 安装 APK、应用列表、启动、强停、清数据、卸载 |
| 文件管理 | 初版 | 浏览 `/sdcard/`、拖拽上传、下载、删除 |
| Logcat | 初版 | 启停日志流、保留最近 1000 行、关键字筛选 |
| Shell / 性能 | 规划中 | 目录结构已预留，后续可扩展 |

拖拽行为：

| 拖入文件 | 动作 |
|---|---|
| `.apk` | `adb install -r <apk>` |
| 其他文件 | `adb push <file> <current remote path>` |

## 项目结构

```text
lib/
  app/
    router/
    theme/
  core/
    adb/
    apps/
    device_actions/
    files/
    logcat/
    providers/
    scrcpy/
  features/
    dashboard/
      presentation/
```

## 开发命令

```bash
flutter pub get
flutter analyze
flutter test
```

本地手动检查运行命令：

```bash
flutter run -d macos
```

## 本地依赖

| 工具 | 用途 |
|---|---|
| `adb` | 设备发现和 shell 命令 |
| `scrcpy` | 外部投屏能力 |
| Flutter Desktop | macOS、Windows、Linux 桌面目标 |

## 代码约定

| 类型 | 约定 |
|---|---|
| 代码注释 | 使用中文描述意图、边界和非显然逻辑 |
| 文档 | 使用中文编写，必要的 API、CLI、类名和协议名保留英文 |
| UI 文案 | 优先走本地化字符串表，避免在 Widget 中散落硬编码文案 |

ADB 和 scrcpy 路径自定义能力后续放入设置模块。
