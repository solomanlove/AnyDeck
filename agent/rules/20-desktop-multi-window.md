---
description: 桌面端窗口与多窗口生命周期规范
globs:
  - "lib/app/window/**/*.dart"
  - "lib/features/**/presentation/**/*.dart"
alwaysApply: false
---

# 桌面端多窗口管理规范

1. **主窗口基础特征**
   - 窗口 ID 为 0，承载 Dashboard 及所有主要 ADB 管理 Tab。
   - 隐藏原生标题栏 (`TitleBarStyle.hidden`)，采用自定义 WindowTitleBar 以便实现应用自定义的主题、边框拖拽和控制按钮（最小化、最大化、关闭）。
   - 拦截原生关闭事件：使用 `windowManager.setPreventClose(true)`，点击关闭时默认**隐藏窗口并最小化到系统托盘**，避免进程意外终止。
   - 双击 macOS Dock 图标或点击托盘图标时，主窗口应自动恢复并重新聚焦 (`windowManager.show()`, `windowManager.focus()`)。

2. **子窗口（独立窗口）设计规范**
   - **单例限制**：打开特定类型子窗口（如模拟器管理窗口、独立投屏窗口）前，必须先获取已存在的所有子窗口列表，如果该类型窗口已处于打开状态，直接将其置顶并聚焦，不允许重复创建同类窗口。
   - **参数传递**：启动子窗口时，使用 `DesktopMultiWindow.createWindow`，并将相关初始化参数（如设备 ID、串口、窗口类型标识等）序列化为 JSON 字符串作为参数传递。
   - **子窗口标题同步**：子窗口加载时，必须解析传入的 JSON 初始化参数，并使用 `DesktopWindowTitleService.setTitle(title)` 同步将本地化后的标题显示在系统原生标题栏中。

3. **托盘与菜单栏**
   - 系统托盘 (`tray_manager`) 监听器必须在应用初始化时注册，并在 dispose 时注销。
   - 退出应用时，必须先调用 `windowManager.setPreventClose(false)` 释放拦截，再调用 `windowManager.destroy()` 和 `exit(0)`，否则会导致应用处于僵死状态。
