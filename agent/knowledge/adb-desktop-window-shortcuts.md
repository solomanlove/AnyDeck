# Knowledge: adb-desktop-window-shortcuts (桌面独立窗口快捷键机制)

## 概述
本文档记录 AdbManage 桌面端窗口的本地快捷键约定。主窗口由 `window_manager` 管理关闭拦截与托盘隐藏，独立子窗口由 `desktop_multi_window` 创建，并通过 `window_manager` 管理当前窗口的关闭、聚焦与标题栏状态。

---

## 1. 支持范围

| 窗口 | 入口类 | 快捷键 | 行为 |
| --- | --- | --- | --- |
| 主窗口 | `DashboardScreen` | `Command + W` | 触发 `windowManager.close()`，由主窗口 close listener 隐藏到托盘 |
| 控制台窗口 | `ConsoleWindowApp` | `Command + W` | 关闭当前控制台子窗口 |
| 模拟器管理窗口 | `EmulatorManagerWindowApp` | `Command + W` | 关闭当前模拟器管理子窗口 |
| 投屏窗口 | `MirrorWindowApp` | `Command + W` | 关闭当前投屏子窗口，仅拦截本地窗口关闭组合键 |
| 应用级退出 | `DashboardScreen` | 连按两次 `Command + Q` | 第一次显示顶部提示并取消退出，2 秒内第二次按下才退出应用 |

投屏窗口复用 `WindowCloseShortcut` 时只处理 `Command + W`，普通按键、`ESC`、全屏与设备键盘映射仍由投屏交互层负责，避免本地窗口快捷键扩大拦截范围。

---

## 2. 实现约定

1. 共享入口位于 `lib/app/window/window_close_shortcut.dart`。
2. `WindowCloseShortcut` 使用 `Focus(autofocus: true)` 保证子窗口打开后能接收快捷键事件。
3. `MainWindowCloseShortcut` 仅用于主窗口，调用 `windowManager.close()` 后继续复用主窗口已有的 hide-to-tray 生命周期。
4. `Command + Q` 由 `DashboardScreen` 的 `CallbackShortcuts` 处理；第一次按下通过 `DashboardSnack.show(...)` 显示顶部提示并记录时间，第二次按下才解除 `window_manager` close 拦截并退出进程。
5. 不要在 macOS 原生层用 `NSEvent.addLocalMonitorForEvents` 拦截 `Command + Q`；如果回调 `return nil`，Flutter 主窗口收不到快捷键，提示和二次退出都会失效。
6. `MainMenu.xib` 中 Quit 菜单项的默认 `q` key equivalent 已移除，避免 AppKit 菜单绕过双按判断。
7. 关闭窗口快捷键通过 `CallbackShortcuts` 注册：

```dart
const SingleActivator(LogicalKeyboardKey.keyW, meta: true)
```

8. 子窗口回调直接调用 `windowManager.close()`，只关闭当前子窗口；主窗口回调同样调用 `windowManager.close()`，但最终行为由 `DashboardScreen.onWindowClose()` 隐藏到托盘。

---

## 3. 后续扩展原则

新增子窗口如果需要支持 `Command + W`，优先复用 `WindowCloseShortcut` 包裹该窗口的 `home` 内容；若窗口存在设备键盘转发、文本编辑器或终端输入捕获，只允许拦截明确的窗口级组合键，避免误拦截用户输入。
