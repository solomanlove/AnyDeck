# AnyDeck 应用单项右键菜单

## 需求与交互

2026-11-06：将 Android 应用页中、融合投屏设置下方的一排单应用操作移至应用项的右键菜单，移除原工具栏及其占位。

- 列表行与网格卡片均支持右键，右键时高亮该应用并直接显示菜单，无需先进入详情。
- 菜单始终针对右键点击的应用，与 Checkbox 批量勾选状态独立；打开菜单不自动读取应用详情或执行设备命令。
- 单击进入详情、Checkbox 批量勾选、批量操作栏、应用安装、列表筛选及网格缩放沿用既有入口。
- 菜单包含原工具栏全部 13 项操作；投屏文案随设备融合模式变化，冻结/解冻随应用启用状态变化。
- HarmonyOS 继续使用已有平台菜单，只展示 HDC 支持的操作。

## 实现入口

| 文件 | 职责 |
| --- | --- |
| `lib/features/apps/dashboard_apps_tab.dart` | 页面状态、选择与刷新；通过 State 自身的 `_updateAppView` 为拆分布局提供状态更新入口 |
| `lib/features/apps/dashboard_apps_view.dart` | 从原超 500 行页面抽出的布局；移除单应用工具栏，保留网格计数及缩放 |
| `lib/features/apps/dashboard_apps_context_menu.dart` | 单项菜单定义、图标及本地化文案、右键定位、平台分流、重复操作拦截 |
| `lib/features/apps/dashboard_apps_actions.dart` | 原工具栏行为迁移为动作处理器，复用既有服务与确认弹窗 |
| `lib/features/apps/dashboard_apps_table_row.dart` / `dashboard_apps_grid.dart` | 列表和网格共用右键入口 |

所有新增或拆分后的 Dart 文件均低于 500 行；菜单使用 Theme 与 `AppThemeSizes`，英文长文案允许换行。

## 命令与行为对应

| 菜单项 | 实现 |
| --- | --- |
| 应用详情 | 既有应用详情 Route |
| 权限管理 | 既有共享权限 Dialog / `AppPermissionsPanel` |
| 撤销所有权限 | 原确认弹窗与 `AppPermissionService.revokeAllRuntimePermissions` |
| 打开手机应用信息 | `am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:<pkg>` |
| 启动 | `monkey -p <pkg> 1` |
| 融合/普通投屏 | `AppMirrorLaunchCoordinator` 按当前设备配置选择既有窗口或创建投屏会话 |
| 强停 | `am force-stop <pkg>` |
| 安装路径 | `pm path <pkg>`，使用既有结果 Dialog 展示完整输出 |
| 清除数据 | 确认后 `pm clear <pkg>` |
| 备份/恢复应用数据 | 复用 `AppDataBackupService` 与原文件选择、确认及反馈流程 |
| 冻结/解冻 | 确认后 `pm disable-user --user 0 <pkg>` / `pm enable <pkg>`，成功后刷新单包状态 |
| 刷新该应用 | `PackagesNotifier.refreshSinglePackage`，保留原刷新进度及成功/失败文案 |

右键菜单创建时捕获设备 ID 与包对象。执行前以及清除数据、撤销权限、冻结/解冻确认后重新检查 mounted、当前设备和在线状态，避免菜单打开后断线或切换设备仍执行操作。菜单或动作未结束时拦截重复右键，异常通过已有 Toast 反馈，finally 释放操作标记。

该变更仅调整主窗口操作入口，继续调用原 ADB、权限、备份和投屏服务；没有新增 Provider、后台轮询或跨 Isolate 通信。

## 验证与回归

- `test/apps_tab_context_menu_test.dart`：13 项菜单、工具栏与占位移除、批量勾选隔离、目标包路由、清除数据确认/取消、冻结/解冻命令、显式单包刷新、断线拦截、重复操作拦截、英文暗色网格菜单以及 HarmonyOS 菜单回归。
- 关联回归：应用筛选、视图切换、应用管理服务、权限操作及融合投屏测试。筛选测试改为单独挂载 `AppsTab`，隔离全 App 启动遮罩、侧边栏同名文案以及宿主环境探测。
- 2026-11-06：上述 6 个测试文件共 38 项测试全部通过，其中新增右键菜单测试 11 项；新增及修改的 9 个 Dart 文件定向 `dart analyze` 无问题，`git diff --check` 通过。
- 全仓 `flutter analyze --no-pub` 无 error，仍返回 38 条既有 warning/info（投屏快捷操作、模拟器、文件预览与诊断脚本等），未修改这些任务外代码。
- 未启动桌面 App、未执行真实设备运维命令；原生右键视觉、实际备份/恢复及投屏需按上述入口进行设备验收。
