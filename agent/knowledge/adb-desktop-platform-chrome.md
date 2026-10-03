# Knowledge: 跨平台桌面窗口与工作区 UI

## 目标与设计

将系统窗口操作与设备业务工具栏分层，避免 Windows/Linux 沿用 macOS 隐藏标题栏后缺少窗口按钮。宿主系统决定窗口样式，连接设备的平台不参与判断。

| 区域 | macOS | Windows | Linux |
| --- | --- | --- | --- |
| 主窗口系统栏 | 隐藏标题文字，保留原生 traffic lights | 36 logical px 自绘标题栏，右侧最小化/最大化或还原/关闭 | 保留 GTK/窗口管理器原生装饰 |
| 主窗口导航 | 顶部预留 36 logical px | 顶部间距 14 logical px | 顶部间距 14 logical px |
| Dashboard 材质 | 保留半透明与 BackdropFilter | ColorScheme 实色表面与导航分层 | ColorScheme 实色表面与导航分层 |
| 独立窗口 | 保留原有隐藏标题栏与原生按钮 | 原生标题栏与系统控制 | 原生标题栏与系统控制 |
| APK 工具栏左侧 | 保留 80 logical px 按钮避让 | 移除 macOS 专用避让 | 移除 macOS 专用避让 |

Windows 固定标题栏位于路由、启动动画与页面工具栏上方，切换设备、模拟器、设置或打开路由内弹窗时均保留窗口控制。标题过长使用省略号；系统栏不重复设备操作。Linux 按钮位置和窗口菜单由桌面环境决定，不假定 GNOME/KDE 使用相同布局。

设计参考：[Windows title bar](https://learn.microsoft.com/en-us/windows/apps/design/basics/titlebar-design)、[GNOME Header Bars](https://developer.gnome.org/hig/patterns/containers/header-bars.html)。这些规范提供交互参考，不代表使用 Flutter 自绘控件即可获得全部原生系统集成。

## 实现与职责

- `lib/app/window/model/desktop_chrome_policy.dart`：集中管理主/子窗口装饰、macOS 避让空间；原生初始化与 UI 使用相同策略。
- `lib/app/window/widget/desktop_window_frame.dart`：主窗口外壳。Windows 标题文字区负责拖动和双击最大化；按钮提供独立点击、键盘焦点、语义标签和 Tooltip。由于位于 MaterialApp.builder，使用 Overlay.wrap 承载 Tooltip。
- `lib/app/window/controller/desktop_caption_controller.dart`：监听聚焦、最大化/还原及全屏事件，仅更新标题栏；有操作防重入、异步结果版本保护和卸载后通知保护，dispose 注销 WindowListener，无轮询。
- `lib/app/window/widget/desktop_workspace_surface.dart`：公共背景和 Material 层级，保证 ListTile 底色与 Ink 在背景上方绘制；Windows/Linux 不挂载工作区 BackdropFilter。
- `lib/features/overview/dashboard_shell.dart` 与 `dashboard_rail.dart`：接入公共表面与侧栏宿主样式；现有 Tab、设备选择和工具按钮逻辑保持原有职责。
- `lib/app/window/desktop_window_title_service.dart`：优先调用 `any_deck/window`，保留 Linux 主 Runner 同步 GTK HeaderBar 的能力；Windows/Linux 子引擎缺少该通道时回退到 window_manager.setTitle。
- `linux/runner/my_application.cc`：注册 desktop_multi_window 子窗口创建回调，为子引擎注册 window_manager 等已有插件，保证窗口配置与设置读取具有对应原生实现。
- 模拟器、控制台、Android API 分布独立窗口在 onGenerateTitle 中同步本地化原生标题；APK 与投屏沿用既有标题同步入口。

没有新增依赖、Provider、持久化设置、ADB 命令或跨窗口广播协议。新增窗口动作中英文资源位于 `app_l10n_settings.dart`；主题仍来自现有设置广播。

## 生命周期与边界

1. 自绘关闭按钮调用 windowManager.close，不直接 destroy 或 exit，主窗口沿用现有 onWindowClose 的隐藏到托盘策略。子窗口原生关闭沿用既有生命周期。
2. 独立投屏窗口使用原生装饰，不额外插入 Flutter 标题栏；原有 Flutter 工具栏高度和输入坐标换算保持不变。系统装饰对外框尺寸、客户区可用尺寸的实际影响仍须在 Windows/Linux 回归。
3. 不更改屏幕/摄像头流、Rust Texture、触控映射、设备息屏恢复或进程清理。
4. Windows 自绘最大化按钮没有新增 Win32 HTMAXBUTTON 命中处理，因此不宣称支持 Windows 11 最大化按钮悬停 Snap Layouts。窗口边缘缩放、DPI、跨显示器移动及系统吸附需要宿主验证。
5. Linux 原生标题栏主题由桌面环境管理，应用主题只控制 Flutter 内容；不强制覆盖用户的窗口按钮排列。

## 自动验证（2026-10-04）

- `flutter test --no-pub test/desktop_window_chrome_test.dart`：9 项通过。覆盖平台策略、700×400 长标题布局、窗口动作与最大化状态、路由外 Tooltip、英文暗色、非 Windows 控制栏不重复、全屏事件、工作区模糊分流、原生标题回退及异步销毁。
- 本次新增与修改的独立 Dart 组件及相关 part 文件定向 `flutter analyze --no-pub`：无诊断。
- 全仓静态分析仍有 43 项任务外诊断，包括 `test/apk_install_coordinator_test.dart` 的 3 处旧方法签名不匹配，以及原有 unused import / lint；本次新增组件无诊断。未修改其他功能或旧测试桩。
- `git diff --check`：通过。
- 未启动或重启桌面应用；未进行 Windows/Linux 构建或原生窗口实测。Widget 测试使用 MethodChannel 桩，不能替代宿主验证。

## 手动回归清单

| 场景 | 验证步骤与预期 |
| --- | --- |
| macOS | 检查左上角按钮避让、标题区拖动、双击、侧栏折叠、明暗主题及关闭到托盘 |
| Windows 主窗口 | 切换全部顶层页面与弹窗，标题栏始终存在；最小化、最大化/还原、关闭到托盘和托盘恢复均正确 |
| Windows 缩放 | 在 100%/150%/200% DPI 与跨显示器移动下检查标题文字、按钮命中、窗口边缘缩放及 700×400 布局 |
| Linux | 分别在 GNOME、KDE 以及可用的 X11/Wayland 环境检查原生标题栏、系统按钮顺序、拖动与窗口菜单 |
| 子窗口 | 打开控制台、模拟器、API 分布、APK、投屏，检查按钮、关闭、快捷键；切换语言后原生标题更新 |
| 投屏 | 竖屏/横屏与窗口缩放后检查客户区、工具栏和触控坐标；断开后检查设备亮屏与资源释放 |
| 无设备与离线 | 标题栏功能独立于连接设备；切换页面不丢失系统控制 |
