# Knowledge: adb-desktop-window-shortcuts (桌面独立窗口快捷键机制)

## 概述
本文档记录 AnyDeck 桌面端窗口的本地快捷键约定。主窗口由 `window_manager` 管理关闭拦截与托盘隐藏，独立子窗口由 `desktop_multi_window` 创建，并通过 `window_manager` 管理当前窗口的关闭、聚焦与标题栏状态。

---

## 1. 支持范围

| 窗口 / 操作 | 入口类 | 默认快捷键 | 行为 |
| --- | --- | --- | --- |
| 主窗口 | `DashboardScreen` | `Command + W` / `Ctrl + W` | 触发 `windowManager.close()`，由主窗口 close listener 隐藏到托盘 |
| 控制台等子窗口 | `WindowCloseShortcut` | `Command + W` / `Ctrl + W` | 关闭当前子窗口 |
| 投屏窗口 | `MirrorWindowApp` | `Command + W` / `Ctrl + W` | 关闭当前投屏子窗口 |
| 打开设置 | `MainWindowCloseShortcut` / `WindowCloseShortcut` | `Command + ,` / `Ctrl + ,` | 主窗口直接跳转，子窗口请求主窗口显示并打开设置 |
| 主窗口聚焦 | `MainWindowCloseShortcut` | 默认 `Command + 1` / `Ctrl + 1` | 在主窗口快捷键范围内显示并聚焦主窗口；可在设置中修改按键 |
| 应用级退出 | 各窗口 → `DashboardScreen` | 连按两次 `Command + Q` / `Ctrl + Q` | 委托主窗口统一确认；第一次显示当前组合键提示，2 秒内第二次才退出 |
| Dock 退出 | macOS `NSApplication` | Dock 图标右键 → 退出 | 使用系统标准退出流程，单次点击立即退出应用 |

默认修饰键为 macOS `Command`、Windows / Linux `Ctrl`；关闭窗口、打开设置和退出软件与主窗口唤起键、投屏操作一样支持直接录入完整组合。未绑定的普通输入、粘贴和 `ESC` 沿用原有交互；用户主动绑定后优先执行对应操作。

---

## 2. 实现约定

1. 共享入口位于 `lib/app/window/window_close_shortcut.dart`。主窗口和独立窗口均通过 `LocalShortcutHandler` 读取当前设置，不再注册写死的 Q、W、逗号组合。
2. `WindowCloseShortcut` 是 ConsumerWidget；关闭只调用当前引擎的 `windowManager.close()`，保留主窗口隐藏到托盘、子窗口释放资源的生命周期。
3. `MainWindowCloseShortcut` 负责当前主窗口的唤起与通用操作，并注册 `any_deck/window_shortcuts` 单向 WindowMethodChannel。子窗口通过 `perform` 方法发送 `openSettings` 或 `quitApp`，主窗口显示并聚焦后调用现有跳转 / 退出回调。关闭请求不允许通过此通道转发，避免误关主窗口。
4. `dashboard_quit_shortcut.dart` 收口主窗口的 `_handleQuitShortcut`，保留 2 秒内连按两次的确认逻辑；提示按当前退出绑定生成，不含固定 Command+Q。状态和资源回收仍归主窗口 State 管理。长按产生的 repeat 由本地 Handler 消费，不会自动完成第二次确认。
5. macOS `MainMenu.xib` 的设置、退出 key equivalent 与 `MainFlutterWindow` 的运行时赋值均已清除，避免 AppKit 在改绑后继续响应旧组合或绕过二次退出。菜单点击、Dock 退出和托盘退出继续沿用原有明确退出入口。
6. 托盘退出项读取 `settings.windowShortcuts` 显示当前组合；清除退出绑定后只显示菜单名称。设置变更和主窗口收到广播时均刷新托盘。
7. `WindowShortcutBridge` 对注册 / 注销使用串行任务队列，只保留待执行任务；通过 owner 身份阻止旧窗口清理覆盖新回调。窗口销毁时注销；`settled` 可用于等待已排队的资源回收。
8. 投屏窗口外层使用 `WindowCloseShortcut(autofocus: false)`，内层 `MirrorShortcutScope` 获取初始焦点；通用组合由外层处理，投屏查找会跳过通用组合，避免一次按下执行两个动作。

---

## 3. 后续扩展原则

新增子窗口优先复用 `WindowCloseShortcut` 包裹 `home`，继承关闭、打开设置和退出三项配置。不要在新增窗口、原生菜单或输入层重复写死默认组合；确认内部焦点和弹窗隔离，避免重复消费事件。

## 4. 设置页与统一快捷键录入

### 需求与入口

- 设置 → 快捷键，集中展示主窗口快捷键，以及投屏侧栏和标题栏操作。
- 关闭窗口、打开设置、退出软件、主窗口唤起键与 20 项投屏操作均通过同一个弹窗直接按键录入，支持自由组合 Command / Meta、Ctrl、Option / Alt、Shift，也支持不带修饰键的 F6、方向键或普通字符。
- 仅按修饰键不生成绑定；录入后预览完整组合，点击保存才生效。取消不写入配置，支持清除、单项恢复默认与投屏整组恢复默认。
- 冲突比较触发键和四种修饰键，同一个主键使用不同修饰键可共存；完全相同时显示占用操作并禁止保存。通用三项与主窗口、投屏交叉校验；改绑或清除后释放原组合，可再分配给其他操作，不存在静态保留键。主窗口唤起键和投屏操作的作用范围分开，可各自使用同一组合。
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
4. 通用三项保存于 `settings.windowShortcuts`，格式为 `action -> 完整绑定 JSON`，未覆盖项使用默认值；广播方法为 `update_window_shortcuts`。源窗口在修改状态和持久化前验证跨组冲突；接收广播使用 `broadcast: false`，允许分组广播过程中短暂的中间状态。
5. `LocalShortcutHandler` 统一拥有 FocusNode 和 `FocusManager.addEarlyKeyEventHandler`，在普通控件 / 设备输入之前匹配完整组合。`MirrorShortcutScope` 提供当前窗口的操作查找，主窗口唤起键和录入控件也复用该公共层。仅当前 Route 且焦点位于对应范围时执行；录入弹窗不会触发原页面快捷键。
6. `MirrorToolbarButton` 通过 `MirrorShortcutTarget` 注册原有点击 / 长按回调。自动隐藏仍保留注册；按钮 Loading、null 回调、平台隐藏和卸载均不能执行对应操作。快捷键 Tooltip 与设置共用完整组合，截图额外展示保存快捷键。
7. 同一次按下只执行一次，repeat 和对应 KeyUp 被消费，修饰键先抬起、配置改变或操作打开弹窗也不会把该 KeyUp 转发给手机。公共 Handler 销毁时移除 early handler 并释放 FocusNode，投屏 Scope 销毁时清空回调表。
8. Android、HarmonyOS、iOS 和单 App 投屏沿用原有按钮的能力门禁与控制通道。此功能不新增 ADB/HDC 命令、设备后台进程或轮询。
9. 录入 UI 位于 `features/overview/widget/keyboard_shortcut_recorder.dart`，录入期间不注册 TextEditingController 或输入法；通过 KeyEvent 读取真实组合，保存前重新验证最新配置中的冲突。

### 测试与回归边界

- 自动化：完整组合编解码、v1 迁移、非法配置回退、修饰键精确匹配、跨组冲突、原组合释放、禁用、恢复默认、SharedPreferences 保存、托盘真实菜单参数、主 / 子窗口广播与动作转发、窗口重建和 Channel 任务清理；三种桌面平台的单键和任意修饰键、本地输入优先级、repeat/up、粘贴、弹窗、按钮禁用和卸载；中英文与 Light/Dark 的实际录入、仅修饰键、取消、清除、默认恢复和主窗口绑定。
- 关联回归：主 / 子窗口关闭与主窗口显示、投屏宽高比和旋转、白板、iOS 工具栏、HarmonyOS 控制、投屏设置、剪贴板与设备快捷设置。
- 验证命令：`flutter test --no-pub` 运行五个快捷键测试及上述关联测试；`flutter analyze --no-pub` 检查快捷键、设置、窗口入口、设置 UI 和相关测试。本次未清理范围外既有告警。
- 本次结果：16 个相关测试文件共 100 项通过；本次静态分析无问题。macOS 菜单 XML 检查、ibtool 资源编译和 MainFlutterWindow 的 Swift 语法检查通过。
- 本次只运行测试与静态检查，未启动桌面 App。真实系统对组合键的占用、已打开的多个原生窗口间切换，以及真机截图 / 录屏 / 设备操作仍需运行态验收。
