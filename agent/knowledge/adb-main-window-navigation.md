# 主窗口导航、帮助中心、底部控制台与系统版本

## 业务入口

1. 模拟器管理统一使用主窗口 `/emulators`。移除独立管理窗口 App、子窗口注册、弹出按钮、macOS Window 菜单和系统托盘入口；AVD、DevEco、iOS Simulator 的运行画面及设备投屏不受影响。
2. 控制台固定在左侧底部、设置上方。点击切换右侧底部面板，不修改 Route、设备选择或设备工具 Tab；打开后可继续操作上方页面。
3. 系统版本位于鸿蒙互联下方，使用 `/system-versions`，迁移期 Tab index 为 `-5`，不要求设备连接。进入时清空设备选择，侧边栏继续显示全局导航。
4. 帮助中心固定在左侧底部 AI MCP 上方，点击后在主窗口内打开 AnyDeck 在线帮助，无需选择设备。

## 文件与职责

| 文件 | 职责 |
| --- | --- |
| `lib/features/overview/dashboard_rail.dart` | 全局与设备侧边栏，按高度计算可见工具数量 |
| `lib/features/overview/dashboard_rail_buttons.dart` | 原有导航按钮、溢出菜单与状态样式 |
| `lib/features/overview/dashboard_rail_footer.dart` | 帮助中心、AI MCP、控制台、设置，控制台与页面选中态相互独立 |
| `lib/features/overview/dashboard_content.dart` | 主窗口内容编排与全局页面加载 |
| `lib/features/console/controller/console_dock_controller.dart` | 面板展开状态与用户高度偏好 |
| `lib/features/console/widgets/console_dock.dart` | 工作区底部分隔条、尺寸约束和独立开窗流程 |
| `lib/app/window/console/console_window_panel.dart` | 底部与独立窗口共享的日志视图和筛选状态 |
| `lib/app/window/console/console_embedded_toolbar.dart` | 窄屏可横向滚动的筛选工具，固定独立窗口和关闭按钮 |
| `lib/app/window/console/console_toolbar_button.dart` | 两种控制台共用的 Icon 操作与主题样式 |
| `lib/app/window/console/console_window_launcher.dart` | 复用既有子窗口单例策略，返回开窗成功/失败 |
| `lib/features/overview/widget/system_versions_page.dart` | 三平台版本列表、适配详情、复制、官方链接与快照时间 |
| `lib/features/overview/controller/system_versions_controller.dart` | 不依赖设备的平台选择状态 |

## 帮助中心入口（2026-11-07）

- 需求：将原有第三方学习网站入口替换为 AnyDeck 帮助中心，中文显示「帮助中心」，英文显示「Help Center」，图标使用 `CupertinoIcons.question_circle`。
- 地址：`https://solomanlove.github.io/AnyDeckWeb/help.html`。复用 `InAppWebViewWidget` 的地址栏、导航、重试和系统浏览器打开能力；页面载入前的标题与侧栏共用本地化文案，载入后沿用网页标题。
- 兼容：内部路由名及文案键 `wanAndroid`、路径 `/wan-android`、Tab index `13` 保持稳定；Android、HarmonyOS、iOS 和未选择设备时均可进入。
- 生命周期：首次访问才创建 WebView，切换其他页面后由现有 `IndexedStack` 保留浏览状态。复用现有 Theme，不新增依赖、Provider、子窗口、后台命令或跨 Isolate 协议，不涉及投屏和设备控制链路。
- 实现：地址与标题位于 `dashboard_content.dart`，图标与点击入口位于 `dashboard_rail_footer.dart`，中英文文案位于 `lib/app/l10n/tables/app_l10n_settings.dart`。
- 自动回归：`test/dashboard_shell_navigation_test.dart` 使用替代原生 WebView 的测试实现，覆盖中英文、明暗主题、无需选择设备、首次访问才创建、实际传给 WebView 的 HTTPS 地址以及往返切页保留状态。自动测试不加载真实网页。
- 验证结果：导航 Shell、全局导航和 Route 共 15 项定向测试通过；本次修改的 Dart 文件定向 analyze 通过；公网帮助页 HTTP 200，页面标题为「帮助中心｜AnyDeck」。
- 人工回归：打开侧栏帮助中心，检查帮助文章和搜索；再切换其他 Tab 后返回；断网时检查既有错误提示与重试入口。不启动桌面 App，原生 WebView 网络加载留待人工验收。

## 侧栏页面选中与服务状态（2026-11-10）

- 需求：投屏接收、文件互传和 AI MCP 的后台运行状态用独立圆点表达，避免设备管理页显示时多个入口同时呈现选中背景。2026-11-17 补充：运行圆点颜色跟随用户选择的主题色。
- 页面选中仅由当前 `selectedToolTabProvider` 决定：保留当前页面的背景、主题色图标与加粗文字；服务运行不再影响这些样式。控制台仍按面板展开状态独立高亮。
- 投屏接收沿用 AirPlay 或 DLNA 任一服务运行即显示圆点的判断；AI MCP 使用 `mcpServerProvider.isRunning`；文件互传通过 `harmonyShareServiceProvider` 复用常驻服务，启用且无错误、发现就绪或正在收发时显示圆点。仅开启开关、启动准备中或启动失败不显示圆点。
- 宽侧栏在右侧显示状态点，窄侧栏在图标右上方显示同一状态组件；悬停状态点显示「服务运行中 / Service running」。颜色复用 Theme 的 `colorScheme.primary`，文案来自 l10n。
- 实现集中在 `dashboard_rail.dart`、`dashboard_rail_buttons.dart`、`dashboard_rail_footer.dart`；不改变 Route、服务启停、文件传输、投屏输入或跨 Isolate 协议，不增加后台任务。文件互传监听仅重建对应入口。
- 自动回归：`test/dashboard_service_navigation_test.dart` 覆盖中英文、Light/Dark、宽窄侧栏、三个服务同时运行、切页迁移高亮、运行中蓝色切换粉色、停服保留页面选中、准备/失败无圆点及收发中状态。`test/dashboard_global_navigation_test.dart` 将互传入口断言更新为现有「文件互传」文案。
- 验证结果：以下四个测试文件共 33 项测试通过，7 个修改及测试 Dart 文件定向 analyze 无问题，`git diff --check` 通过。
- 人工回归：启动桌面 App 后分别启停三个服务，切换页面并悬停运行圆点；切换主题色、缩窄窗口检查右上角状态点与提示。自动测试使用替代服务，不启动桌面 App 或真实服务。

```bash
flutter test --no-pub test/dashboard_service_navigation_test.dart test/dashboard_global_navigation_test.dart test/dashboard_shell_navigation_test.dart test/receiver_dashboard_tab_test.dart
flutter analyze --no-pub lib/features/overview/dashboard_rail.dart lib/features/overview/dashboard_rail_buttons.dart lib/features/overview/dashboard_rail_footer.dart lib/features/harmony_share/controller/harmony_share_providers.dart lib/app/l10n/tables/app_l10n_settings.dart test/dashboard_service_navigation_test.dart test/dashboard_global_navigation_test.dart
git diff --check
```

## 控制台布局与生命周期

- 默认关闭，初始高度 260px。8px 分隔条使用 `resizeUpDown` 光标；拖动时限制实际高度，至少保留 180px 工作区。
- 窗口缩小时只约束实际布局，不覆盖用户选择的高度；短到无法容纳面板时暂时隐藏，恢复尺寸后重新展示。
- 底部面板挂在主窗口右侧 Shell，Route 和设备变化不重建已有工作区；关闭时释放日志视图的搜索和滚动控制器，日志采集继续运行。
- 独立窗口创建期间禁用重复操作；创建或置前成功后收起底部面板，失败则保留日志并提示重试。macOS 和托盘的独立控制台入口保留。
- 复用 `logHistoryProvider`、有界内存历史、150ms 批处理、虚拟列表和既有跨 Isolate 日志协议，不增加日志轮询、ADB 命令或新依赖。

## 系统版本页

- 直接复用现有 Android、HarmonyOS、iOS 数据模型与详情组件；不更新或推断资料中的版本事实、统计占比及发布日期。
- 主窗口使用标准 Dashboard 标题。窄窗口将平台切换器放到第二行，高度受限时将它放回标题右侧，为正文保留空间。
- 三个平台通过 `VersionDistributionLayout` 共用列表和详情布局。默认字号下，内容区达到 720 逻辑像素时左右分栏，列表最多占 40%。更窄时列表在上、详情在下，两区各自纵向滚动。
- 详情按实际栏宽换行。默认字号下，并排的资料组在可用宽度低于 600 逻辑像素时上下排列，单组资料使用完整栏宽。分栏断点随正文字号缩放。主窗口和独立窗口的标题、平台切换器及页脚固定。正文可用高度低于 320 逻辑像素时，可在正文内上下滚动以访问列表、详情及历史记录。
- 布局回归覆盖三平台双栏与单栏的正文换行、版本切换与复制、滚轮在正文边界和固定栏上的行为，以及矮窗口在 200% 字号下的页脚、长代号和历史记录。
- 新增文案使用 zh/en 字典，新增容器与按钮使用现有 Theme。沿用资料组件原有的品牌配色及数据来源说明。

## 多窗口与兼容边界

- `main.dart` 不再把未知子窗口类型回退到模拟器管理；未知或已移除类型会关闭该子窗口。
- `generate_app_window_run_configs.sh` 只生成控制台和在线设备的投屏配置，不再生成模拟器管理配置。历史自行保存的 IDE 配置需要用户删除，旧类型不会启动管理页。
- 控制台主题、语言与跨窗口日志继续走原有设置广播。面板开关和高度仅属于主窗口，无需跨 Isolate 同步。
- 本次不调整投屏协议、触控坐标、进程控制、文件传输或设备物理屏幕状态。

## 验证与人工回归

独立提交副本的 89 项测试通过；并行图标变更提交后，集成版本的 82 项定向测试通过（包含导航图标测试）。Swift 语法解析通过；本次目标文件定向 analyze 通过。自动测试覆盖 Route 解析和命名路径、真实 Dashboard 的设备上下文保持、系统版本进入时清除设备选择、侧边栏顺序、面板拖动与重新打开、日志更新、独立窗口失败与复用、最小尺寸、中英文及明暗主题、模拟器无弹出入口和 CLI 配置生成。

```bash
flutter test --no-pub test/console_dock_test.dart test/dashboard_global_navigation_test.dart test/dashboard_shell_navigation_test.dart test/app_window_run_configs_test.dart test/dashboard_route_test.dart test/emulator_panel_test.dart test/console_diagnostics_test.dart test/platform_version_distribution_test.dart test/emulator_process_test.dart test/emulator_launch_test.dart test/emulator_connection_test.dart test/platform_version_distribution_launcher_test.dart test/apk_window_open_test.dart test/local_logging_test.dart test/desktop_window_chrome_test.dart test/app_navigation_icons_test.dart
swiftc -frontend -parse macos/Runner/MainFlutterWindow.swift
git diff --check
```

完整 Dashboard 旧测试 `test/widget_test.dart` 在未修改的 HEAD 临时副本中同样 10 项全部失败，包含旧 UI 断言、闪屏遮挡和异步计时器；不以该旧测试证明新增功能通过，也不扩展本次代码范围修复旧业务。

按仓库要求不启动桌面 App 或模拟器。原生菜单实际显示、真实拖动手感、独立控制台跨 Engine 日志、设备投屏期间的视觉与性能仍需桌面人工验收。
