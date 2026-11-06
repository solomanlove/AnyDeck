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
- 主窗口唤起键与 20 项投屏操作均通过弹窗直接按键录入，支持自由组合 Command / Meta、Ctrl、Option / Alt、Shift，也支持不带修饰键的 F6、方向键或普通字符。
- 仅按修饰键不生成绑定；录入后预览完整组合，点击保存才生效。取消不写入配置，支持清除、单项恢复默认与投屏整组恢复默认。
- 冲突比较触发键和四种修饰键，同一个主键使用不同修饰键可共存；完全相同时显示占用操作并禁止保存。关闭、打开设置和退出的标准组合键保留原约定，录入时显示具体占用项。
- 绑定普通字符或编辑组合键后，该组合在目标窗口内优先执行用户指定的操作；未配置的输入继续沿用原链路。

### 默认按键

下表保留已有默认值：macOS 初始使用 `Command + Option`，Windows / Linux 初始使用 `Ctrl + Alt`。这些只是默认组合，可通过直接录入自由更换修饰键与触发键。

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

1. `keyboard_shortcut_binding.dart` 保存触发键的 `keyId` 和 `control / alt / shift / meta` 四个独立布尔值，负责录入、精确匹配、标签和 JSON 校验。左右修饰键等价；修饰键自身不能作为触发键。`mirror_shortcut.dart` 统一操作目录、默认组合与冲突校验。
2. 投屏设置继续使用 `settings.mirrorShortcuts`，新格式为 `{"version":2,"bindings":{"action":{"keyId":123,"control":true,"alt":false,"shift":true,"meta":false}}}`；只保存覆盖项，`keyId:null` 且修饰键全 false 表示禁用。兼容旧的 `action -> 字符串` 配置，按原平台前缀迁移后保留用户按键与禁用状态；非法值或重复绑定整体回退默认值。
3. 主窗口使用 `settings.mainWindowShortcut` 保存完整组合，缺失或损坏时沿用 `settings.showWindowShortcutKey` 的旧值；显式 disabled 不再回退旧按键。`ShortcutSettings` mixin 统一持久化和广播，投屏继续使用 `update_mirror_shortcuts`，主窗口使用 `update_main_window_shortcut`，参数均为 JSON 字符串，接收端使用 `broadcast: false` 防止循环广播。
4. `LocalShortcutHandler` 统一拥有 FocusNode 和 `FocusManager.addEarlyKeyEventHandler`，在普通控件 / 设备输入之前匹配完整组合。`MirrorShortcutScope` 提供当前窗口的操作查找，主窗口唤起键和录入控件也复用该公共层。仅当前 Route 且焦点位于对应范围时执行；录入弹窗不会触发原页面快捷键。
5. `MirrorToolbarButton` 通过 `MirrorShortcutTarget` 注册原有点击 / 长按回调。自动隐藏仍保留注册；按钮 Loading、null 回调、平台隐藏和卸载均不能执行对应操作。快捷键 Tooltip 与设置共用完整组合，截图额外展示保存快捷键。
6. 同一次按下只执行一次，repeat 和对应 KeyUp 被消费，修饰键先抬起、配置改变或操作打开弹窗也不会把该 KeyUp 转发给手机。公共 Handler 销毁时移除 early handler 并释放 FocusNode，投屏 Scope 销毁时清空回调表。
7. Android、HarmonyOS、iOS 和单 App 投屏沿用原有按钮的能力门禁与控制通道。此功能不新增 ADB/HDC 命令、设备后台进程或轮询。
8. 录入 UI 位于 `features/overview/widget/keyboard_shortcut_recorder.dart`，录入期间不注册 TextEditingController 或输入法；通过 KeyEvent 读取真实组合，保存前重新验证最新配置中的冲突。

### 测试与回归边界

- 自动化：完整组合编解码、v1 迁移、非法配置回退、修饰键精确匹配、冲突、禁用、恢复默认、SharedPreferences 保存、主 / 子窗口广播；三种桌面平台的单键和任意修饰键、本地输入优先级、repeat/up、粘贴、弹窗、按钮禁用和卸载；中英文与 Light/Dark 的实际录入、仅修饰键、取消、清除、默认恢复和主窗口绑定。
- 关联回归：主 / 子窗口关闭与主窗口显示、投屏宽高比和旋转、白板、iOS 工具栏、HarmonyOS 控制、投屏设置、剪贴板与设备快捷设置。
- 验证命令：`flutter test --no-pub` 运行四个快捷键测试及上述关联测试；`flutter analyze --no-pub` 检查快捷键、设置、窗口入口、设置 UI 和相关测试。本次未清理范围外既有告警。
- 本次结果：13 个相关测试文件共 71 项通过；12 个静态分析目标无问题。
- 本次只运行测试与静态检查，未启动桌面 App。真实系统对组合键的占用、已打开的多个原生窗口间切换，以及真机截图 / 录屏 / 设备操作仍需运行态验收。
