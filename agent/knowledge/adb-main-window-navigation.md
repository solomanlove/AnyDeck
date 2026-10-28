# 主窗口导航、底部控制台与系统版本

## 业务入口

1. 模拟器管理统一使用主窗口 `/emulators`。移除独立管理窗口 App、子窗口注册、弹出按钮、macOS Window 菜单和系统托盘入口；AVD、DevEco、iOS Simulator 的运行画面及设备投屏不受影响。
2. 控制台固定在左侧底部、设置上方。点击切换右侧底部面板，不修改 Route、设备选择或设备工具 Tab；打开后可继续操作上方页面。
3. 系统版本位于鸿蒙互联下方，使用 `/system-versions`，迁移期 Tab index 为 `-5`，不要求设备连接。进入时清空设备选择，侧边栏继续显示全局导航。

## 文件与职责

| 文件 | 职责 |
| --- | --- |
| `lib/features/overview/dashboard_rail.dart` | 全局与设备侧边栏，按高度计算可见工具数量 |
| `lib/features/overview/dashboard_rail_buttons.dart` | 原有导航按钮、溢出菜单与状态样式 |
| `lib/features/overview/dashboard_rail_footer.dart` | 玩安卓、AI MCP、控制台、设置，控制台与页面选中态相互独立 |
| `lib/features/overview/dashboard_content.dart` | 主窗口内容编排与全局页面加载 |
| `lib/features/console/controller/console_dock_controller.dart` | 面板展开状态与用户高度偏好 |
| `lib/features/console/widgets/console_dock.dart` | 工作区底部分隔条、尺寸约束和独立开窗流程 |
| `lib/app/window/console/console_window_panel.dart` | 底部与独立窗口共享的日志视图和筛选状态 |
| `lib/app/window/console/console_embedded_toolbar.dart` | 窄屏可横向滚动的筛选工具，固定独立窗口和关闭按钮 |
| `lib/app/window/console/console_toolbar_button.dart` | 两种控制台共用的 Icon 操作与主题样式 |
| `lib/app/window/console/console_window_launcher.dart` | 复用既有子窗口单例策略，返回开窗成功/失败 |
| `lib/features/overview/widget/system_versions_page.dart` | 三平台版本列表、适配详情、复制、官方链接与快照时间 |
| `lib/features/overview/controller/system_versions_controller.dart` | 不依赖设备的平台选择状态 |

## 控制台布局与生命周期

- 默认关闭，初始高度 260px。8px 分隔条使用 `resizeUpDown` 光标；拖动时限制实际高度，至少保留 180px 工作区。
- 窗口缩小时只约束实际布局，不覆盖用户选择的高度；短到无法容纳面板时暂时隐藏，恢复尺寸后重新展示。
- 底部面板挂在主窗口右侧 Shell，Route 和设备变化不重建已有工作区；关闭时释放日志视图的搜索和滚动控制器，日志采集继续运行。
- 独立窗口创建期间禁用重复操作；创建或置前成功后收起底部面板，失败则保留日志并提示重试。macOS 和托盘的独立控制台入口保留。
- 复用 `logHistoryProvider`、有界内存历史、150ms 批处理、虚拟列表和既有跨 Isolate 日志协议，不增加日志轮询、ADB 命令或新依赖。

## 系统版本页

- 直接复用现有 Android、HarmonyOS、iOS 数据模型与详情组件；不更新或推断资料中的版本事实、统计占比及发布日期。
- 使用标准 Dashboard 标题，移除窗体关闭按钮；窄屏将平台切换放到第二行。
- 双栏内容至少保留 980px 宽度，窄窗口可横向滚动。工作区被控制台压缩时提供纵向滚动，避免固定头部和详情布局溢出。
- Android 详情的版本和占比徽章支持换行，兼容英文长文案。
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
