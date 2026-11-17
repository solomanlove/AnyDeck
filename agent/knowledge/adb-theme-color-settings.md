# AnyDeck 主题色设置

## 需求与入口

2026-11-17：在“设置 → 常规”新增“主题色”，支持绿色、蓝色、紫色、橙色、粉色和青色。默认沿用原绿色；选择后立即刷新、自动保存。颜色名称和设置说明支持中英文，设置全局搜索可按颜色名称定位。

## 实现与边界

- `lib/app/theme/app_theme_color.dart` 集中定义主色、稳定枚举名称及本地化 key。`buildAppTheme` 接收 `themeColor`，同时构建 Light/Dark 的 ColorScheme 和按钮、Checkbox、Radio 主色。
- `AppSettings.themeColor` 默认 `green`；`copyWith` 保留未修改字段。SharedPreferences key 为 `settings.themeColor`，保存枚举名称；缺失或未知名称回退绿色，兼容旧版本。
- 外观保存方法收口到 `app_settings_appearance.dart`，将原 `setThemeMode` 一并移入，保持 Controller 在 500 行以内。主题色修改等待初始设置加载，避免旧配置覆盖用户选择。
- 主窗口和投屏、APK 详情、控制台、版本分布、DLNA 的 Flutter 窗口均接入同一主色。设置菜单、开关和主侧栏高亮使用 Theme；在线、成功、警告和设备品牌等业务颜色保留原语义。
- 主题色下拉菜单复用设置页公共选择器，支持色点预览，并将色点宽度计入菜单测量，保持按钮与菜单边缘对齐。中英文文案位于独立的 `app_l10n_theme.dart`。
- 无新增插件、Provider、后台进程或设备命令。原生视频窗口的明暗外观继续走原有接口；主题色作用于 Flutter 控件。

## 跨窗口通信

| 项目 | 约定 |
| --- | --- |
| Method | `update_theme_color` |
| 参数 | `green`、`blue`、`purple`、`orange`、`pink` 或 `teal` 字符串 |
| 发送 | 修改窗口保存设置后，复用现有广播；子窗口先通知 `any_deck/settings_main`，再同步其他活动窗口 |
| 接收 | 等待初始加载后只更新内存，不回写 Preference、不再次广播，避免旧值回写及广播循环 |
| 异常 | 忽略非字符串及未知名称；窗口关闭或广播失败沿用既有容错与 Timeout |

## 验证与回归

```bash
flutter --no-version-check test --no-pub \
  test/app_theme_test.dart test/app_theme_color_settings_test.dart \
  test/settings_theme_color_test.dart test/theme_window_wiring_test.dart \
  test/dashboard_service_navigation_test.dart test/app_settings_test.dart \
  test/settings_review_test.dart test/settings_workspace_test.dart \
  test/dashboard_shell_navigation_test.dart test/autostart_setting_control_test.dart \
  test/mirror_settings_dialog_test.dart test/core/dlna/dlna_player_bridge_test.dart
git diff --check
```

- 自动测试覆盖全部颜色 × Light/Dark、System 跟随、默认兼容、保存重建、初始化竞态、主子窗口广播、非法参数以及接收端不回写和不循环。
- 实际 Dashboard 覆盖中英文 × 明暗主题 × 900/1600px、颜色预览、菜单对齐、搜索定位、切回绿色、即时保存和通知开关颜色；实际 Console 子窗口验证蓝色切换为紫色。
- 定向 analyze 使用 `--no-fatal-infos`；当前 Flutter SDK 对仓库沿用的 Material 导入和本地化委托给出弃用 info，未进行无关的包迁移。
- 验证结果：上述 12 个测试文件共 85 项全部通过；本次 Dart 修改文件定向 analyze 无 error/warning，仅 29 项 SDK 弃用 info，退出码为 0。新文件及测试格式检查、`git diff --check` 均通过。
- 未启动桌面 App。真实多 Engine 广播、实际 DPI 与原生窗口视觉仍属于桌面人工验收范围。

人工回归：打开设置和任一子窗口，依次选择六种颜色，确认按钮、选中导航和设置开关同步；切换浅色/深色/跟随系统后颜色保持；重启确认恢复选择，设备在线绿点与成功提示继续使用业务状态色。

## 2026-11-17 全页面交互颜色补齐

对 `lib/` 中 `AppPalette.primary`、命名绿色、绿色十六进制值及 `brandGreen`、`_overviewAccent` 等别名逐处检查，修正原设置页之外遗留的绿色交互。改动只涉及配色和相关回归，不改变设备命令与 Provider 生命周期。

| 范围 | 跟随主题的内容 |
| --- | --- |
| MCP、消息 | 服务启动按钮、开关、目标消息边框和背景、屏蔽列表图标 |
| 开发者、更新与接收名称 | 工具图标、操作按钮、更新进度、接收名称输入焦点边框 |
| 设备、模拟器、AirPlay | 连接/投屏/启动入口、模拟器选择背景、打开投屏按钮 |
| 概览 | 卡片图标、API badge、容量卡背景/边框及进度条 |
| 应用与投屏 | 启动/权限/开启 Wi-Fi 快捷操作、融合投屏开关、鼠标轨迹回放按钮及进度 |
| 截图、布局、日志、网页 | 连续保存选中按钮、布局树选中背景、画布选区、日志恢复按钮、地址栏图标 |

- 业务 UI 从 `Theme.of(context).colorScheme.primary/onPrimary` 读取交互主色；`SettingsDeveloperEntry.brandGreen` 仅作为可选覆盖，默认随当前 Theme 更新。
- 两个布局预览 Painter 由 Widget 注入 `selectionColor`，`shouldRepaint` 比较颜色，确保切换主题后已有选区重新绘制；固定全量边界、Hover、标尺及用户画笔不受影响。
- 概览成功状态与主题装饰分离；在线、Root、充电、运行/成功/环境就绪等继续使用固定状态色。Android Logo、ANSI/Logcat 语法、图表数据序列、布尔属性及调色板中的绿色保留业务含义。网络页面剩余绿色用于成功 SnackBar，交互已使用 Theme。
- 公共 `appColors` helper 在标准 `ThemeData` 未安装扩展时回退到对应明暗语义色，支持公共组件单独复用，避免新接入成功语义色后出现空值异常。
- 新增 `control_theme_color_test.dart`、`device_theme_color_test.dart`、`theme_feature_controls_test.dart`、`screenshot_layout_theme_test.dart`、`logcat_webview_theme_test.dart`，验证非绿色主题、同一组件实时换色、输入及选择保留、回调仍可用，并对实际 Painter 选区像素取样。
- 旧回归 fixture 补齐原生窗口广播隔离；截图布局回归使用固定 PNG，并隔离侧栏设置/MCP/Share/概览依赖，避免测试等待引擎图像编码或启动真实服务。WebView 测试恢复有效的平台占位实现，避免插件不允许设置空实例的断言。

新增回归与关键旧回归入口：

```bash
flutter --no-version-check test --no-pub \
  test/control_theme_color_test.dart test/device_theme_color_test.dart \
  test/theme_feature_controls_test.dart test/screenshot_layout_theme_test.dart \
  test/logcat_webview_theme_test.dart test/app_theme_test.dart \
  test/messages_source_widget_test.dart test/developer_mode_test.dart \
  test/screenshot_layout_merge_test.dart
```

本轮共验证 31 个相关测试文件、177 项测试全部通过，包含主题设置与多窗口、MCP、消息、开发者、模拟器、概览、接收端、截图/编辑/布局、Logcat/WebView、应用视图与投屏快捷操作。定向 analyze 无 error；保留 HEAD 已有的 `_OverviewHeroCard.tooltip` 未使用参数 warning、两项既有 info 及 SDK 弃用 info，使用 `--no-fatal-infos --no-fatal-warnings` 验证通过。新文件格式与 `git diff --check` 通过，未启动桌面 App。
