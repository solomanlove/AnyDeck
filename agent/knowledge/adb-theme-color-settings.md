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
