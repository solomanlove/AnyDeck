# Knowledge: adb-desktop-window-shortcuts (桌面独立窗口快捷键机制)

## 概述
本文档记录 AdbManage 桌面端独立子窗口的本地快捷键约定。独立子窗口由 `desktop_multi_window` 创建，并通过 `window_manager` 管理当前窗口的关闭、聚焦与标题栏状态。

---

## 1. 支持范围

| 窗口 | 入口类 | 快捷键 | 行为 |
| --- | --- | --- | --- |
| 控制台窗口 | `ConsoleWindowApp` | `Command + W` | 关闭当前控制台子窗口 |
| 模拟器管理窗口 | `EmulatorManagerWindowApp` | `Command + W` | 关闭当前模拟器管理子窗口 |

投屏窗口暂不复用该快捷键封装。投屏窗口需要将部分键盘输入转发给 Android 设备，并已在投屏交互层单独处理 `ESC`、全屏与设备按键映射，避免本地窗口快捷键和设备键盘注入职责混淆。

---

## 2. 实现约定

1. 共享入口位于 `lib/app/window/window_close_shortcut.dart`。
2. `WindowCloseShortcut` 使用 `Focus(autofocus: true)` 保证子窗口打开后能接收快捷键事件。
3. 快捷键通过 `CallbackShortcuts` 注册：

```dart
const SingleActivator(LogicalKeyboardKey.keyW, meta: true)
```

4. 回调直接调用 `windowManager.close()`，只关闭当前子窗口，不触发主窗口的托盘隐藏逻辑。

---

## 3. 后续扩展原则

新增子窗口如果需要支持 `Command + W`，优先复用 `WindowCloseShortcut` 包裹该窗口的 `home` 内容；若窗口存在设备键盘转发、文本编辑器或终端输入捕获，需要先确认快捷键职责边界，避免误拦截用户输入。
