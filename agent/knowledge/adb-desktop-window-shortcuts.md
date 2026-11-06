# Knowledge: adb-desktop-window-shortcuts (桌面独立窗口快捷键机制)

## 概述
本文档记录 AnyDeck 桌面端窗口的本地快捷键约定。主窗口由 `window_manager` 管理关闭拦截与托盘隐藏，独立子窗口由 `desktop_multi_window` 创建，并通过 `window_manager` 管理当前窗口的关闭、聚焦与标题栏状态。

---

## 1. 支持范围

| 窗口 | 入口类 | 快捷键 | 行为 |
| --- | --- | --- | --- |
| 主窗口 | `DashboardScreen` | `Command + W` / `Ctrl + W` | 触发 `windowManager.close()`，由主窗口 close listener 隐藏到托盘 |
| 控制台等子窗口 | `WindowCloseShortcut` | `Command + W` / `Ctrl + W` | 关闭当前子窗口 |
| 投屏窗口 | `MirrorWindowApp` | `Command + W` / `Ctrl + W` | 关闭当前投屏子窗口 |
| 主窗口设置 | `DashboardScreen` | `Command + ,` / `Ctrl + ,` | 打开设置页 |
| 主窗口聚焦 | `MainWindowCloseShortcut` | 默认 `Command + 1` / `Ctrl + 1` | 在主窗口快捷键范围内显示并聚焦主窗口；可在设置中修改按键 |
| 应用级退出 | `DashboardScreen` | 连按两次 `Command + Q` / `Ctrl + Q` | 第一次显示顶部提示并取消退出，2 秒内第二次按下才退出应用 |
| Dock 退出 | macOS `NSApplication` | Dock 图标右键 → 退出 | 使用系统标准退出流程，单次点击立即退出应用 |

macOS 使用 `Command`，Windows / Linux 使用 `Ctrl`。`WindowCloseShortcut` 只负责关闭窗口；投屏工具操作由 `MirrorShortcutScope` 在设备键盘映射之前处理。普通输入、现有粘贴和 `ESC` 退出全屏仍沿用原有交互链路。

---

## 2. 实现约定

1. 共享入口位于 `lib/app/window/window_close_shortcut.dart`。
2. `WindowCloseShortcut` 使用 `Focus(autofocus: true)` 保证子窗口打开后能接收快捷键事件。
3. `MainWindowCloseShortcut` 仅用于主窗口，调用 `windowManager.close()` 后继续复用主窗口已有的 hide-to-tray 生命周期。
4. `Command + Q` 由 `DashboardScreen` 的 `CallbackShortcuts` 处理；第一次按下通过 `DashboardSnack.show(...)` 显示顶部提示并记录时间，第二次按下才解除 `window_manager` close 拦截并退出进程。
5. 不要在 macOS 原生层用 `NSEvent.addLocalMonitorForEvents` 拦截 `Command + Q`；如果回调 `return nil`，Flutter 主窗口收不到快捷键，提示和二次退出都会失效。
6. `MainMenu.xib` 中 Quit 菜单项的默认 `q` key equivalent 已移除，避免 AppKit 菜单绕过双按判断。
7. `AppDelegate` 不拦截 `applicationShouldTerminate`。Dock 的“退出”属于明确的系统退出动作，应一次生效；主窗口关闭按钮仍由 `window_manager` 拦截并隐藏到托盘。
8. 关闭窗口快捷键通过 `CallbackShortcuts` 注册：

```dart
SingleActivator(
  LogicalKeyboardKey.keyW,
  meta: Platform.isMacOS,
  control: !Platform.isMacOS,
)
```

9. 子窗口回调直接调用 `windowManager.close()`，只关闭当前子窗口；主窗口回调同样调用 `windowManager.close()`，但最终行为由 `DashboardScreen.onWindowClose()` 隐藏到托盘。

---

## 3. 后续扩展原则

新增子窗口如果需要支持标准窗口关闭组合键，优先复用 `WindowCloseShortcut` 包裹该窗口的 `home` 内容；若窗口存在设备键盘转发、文本编辑器或终端输入捕获，只允许拦截明确的窗口级组合键，避免误拦截用户输入。

## 4. 设置页与可修改的投屏快捷键

### 需求与入口

- 设置 → 快捷键，集中展示主窗口快捷键，以及投屏侧栏和标题栏操作。
- 主窗口聚焦按键沿用已有配置和支持字符；旧的无效值回退到 `1`。关闭、打开设置和双按退出属于固定窗口约定。
- 投屏操作可选择字母、数字、方向键或 Enter，可设为“未设置”，并可整体恢复默认。固定前缀为 macOS `Command + Option`，Windows / Linux `Ctrl + Alt`；不抢占普通输入和 `Command/Ctrl + V`。
- 不同操作不能使用同一按键；冲突时提示已占用的操作，原绑定保持不变。若需交换按键，先禁用其中一个绑定。

### 默认按键

下表按键均需加上述固定前缀。

| 操作 | 默认按键 | 操作 | 默认按键 |
| --- | --- | --- | --- |
| 电源 | P | 设备物理屏幕亮灭 | O |
| 音量增加 | ↑ | 音量降低 | ↓ |
| 返回 | B | Home | H |
| 最近任务 | M | 输入电脑剪贴板 | V |
| 手机剪贴板 | C | 前台窗口 | F |
| 截图并复制 | S | 截图并保存 | D |
| 白板开关 | W | 开始 / 停止录屏 | R |
| 鼠标轨迹录制 / 回放 / 暂停 | T | 设备设置 | E |
| 全屏开关 | Enter | 窗口置顶开关 | A |
| 投屏设置 | Q | 重新连接 | X |

### 实现与窗口同步

1. `lib/app/shortcuts/mirror_shortcut.dart` 是操作、默认按键、冲突校验和展示标签的唯一目录。持久化使用 `settings.mirrorShortcuts` JSON，仅保存覆盖项；非法值或重复绑定整体回退默认值。
2. `AppSettingsController` 的 `ShortcutSettings` mixin 负责持久化、加载和广播。`update_mirror_shortcuts` 参数为 JSON 字符串，沿用现有主窗口单向 Channel 和子窗口枚举链路；接收端使用 `broadcast: false` 防止循环广播。
3. `MirrorShortcutScope` 每个投屏窗口独立创建，使用 `FocusManager.addEarlyKeyEventHandler` 在设备输入之前处理本地组合键，标准关闭组合键同样优先调用原有窗口关闭入口。仅焦点位于该 Scope 且当前 Route 可用时执行；弹窗、其他窗口和普通文本输入不触发投屏操作。
4. `MirrorToolbarButton` 通过 `MirrorShortcutTarget` 注册原有点击 / 长按回调。自动隐藏仍保留注册；按钮 Loading、null 回调、平台隐藏和卸载均不能执行对应操作。快捷键 Tooltip 与设置共用配置，截图额外展示保存快捷键。
5. 同一次按下只执行一次，repeat 和对应 KeyUp 被消费，修饰键先抬起或操作打开弹窗也不会把该 KeyUp 转发给手机。Scope 销毁时移除 early handler 并释放 FocusNode、回调表。
6. Android、HarmonyOS、iOS 和单 App 投屏沿用原有按钮的能力门禁与控制通道。此功能不新增 ADB/HDC 命令、设备后台进程或轮询。
7. 投屏页面与标题栏、截图 / 前台窗口动作拆为独立 part 文件，新增及拆分文件均低于 500 行，生命周期仍归原 State 管理。

### 测试与回归边界

- 自动化：配置编解码、非法配置回退、冲突、禁用、恢复默认、SharedPreferences 保存、主 / 子窗口广播；三种桌面平台的本地按键优先级、repeat/up、普通输入、粘贴、弹窗、按钮禁用和卸载；中英文与 Light/Dark 设置 UI。
- 关联回归：主 / 子窗口关闭与主窗口显示、投屏宽高比和旋转、白板、iOS 工具栏、HarmonyOS 控制、投屏设置、剪贴板与设备快捷设置。
- 验证结果：4 个新增测试文件与 9 个关联测试文件合计 62 项通过；本次 22 个静态分析目标无问题。全仓初次检查还报告其他模块的既有告警，本次未清理范围外代码。
- 本次只运行测试与静态检查，未启动桌面 App。真实系统对组合键的占用、已打开的多个原生窗口间切换，以及真机截图 / 录屏 / 设备操作仍需运行态验收。
