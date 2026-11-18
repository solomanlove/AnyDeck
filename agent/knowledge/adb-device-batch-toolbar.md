# AnyDeck 设备批量管理工具栏

## 需求与交互

2026-11-18：设备管理进入批量模式后，直接显示以下单行操作：

`全选(x) → 开始镜像 → 截屏 → 录屏 → 安装App → 推送文件 → 执行脚本 → 定时任务 → 删除设备`

- `x` 为所有已选注册设备数量；全选 Checkbox 仅修改当前筛选结果，并保留部分选中的三态。
- 选择范围、已选总数与筛选隐藏的已选数量通过全选区域的 Tooltip 说明。
- 列表模式在原表头位置显示工具栏，隐藏设备名称、连接状态、系统版本与操作表头；退出管理恢复表头并清空选择。
- 设备墙和空筛选结果继续提供工具栏；窄窗口横向滚动，保持按钮顺序和单行布局。

## 实现与执行边界

| 位置 | 职责 |
| --- | --- |
| `lib/features/devices/dashboard_devices_batch_bar.dart` | 全选三态、计数 Tooltip、直接操作按钮、平台能力和执行防重入 |
| `lib/features/devices/dashboard_devices_view.dart` | 在列表表头位置切换批量工具栏，保留设备墙和空结果入口 |
| `lib/features/devices/dashboard_devices_panel.dart` | 管理模式和批量操作执行状态 |
| `lib/app/l10n/tables/app_l10n_device_workspace.dart` | 中英文计数与紧凑操作文案 |

按钮沿用 `_executeWorkspaceBatch` 与既有批量处理器，不新增 CLI 或依赖：
镜像面向在线设备；截屏、录屏、安装、推送和定时任务面向在线 Android；脚本支持在线 Android/HarmonyOS，仍由 ADB/HDC 执行；删除允许离线设备，保留原确认流程。
执行期间禁用批量动作，并在 `finally` 中检查 `mounted` 后复位，阻止直接按钮重复提交。
颜色继续取自 Theme / ColorScheme，删除使用 error 语义色；无新增 Provider 或跨 Isolate 通信。

## 测试与验证

- `test/device_batch_toolbar_test.dart`：中英文、Light/Dark、宽窄窗口与放大字号、固定顺序、横向滚动、表头替换、全选三态及平台禁用、定时任务直达。
- `test/dashboard_device_workspace_test.dart`：跨视图和筛选保留勾选，隐藏数量 Tooltip 与退出清空。
- `test/batch_script_tool_path_test.dart`：直接入口仍使用用户配置的 ADB/HDC 路径，iOS 脚本禁用。
- `test/devices_audit_theme_test.dart`：直接定时任务入口与主题色。
- 回归设备响应式、列表排序、分组、右键菜单及共享 fixture 的既有测试。

验证使用 `script/flutter.sh test --no-pub` 和 `script/flutter.sh analyze --no-pub --no-fatal-infos --no-fatal-warnings`；不启动完整 App，不操作真实设备。

本轮 14 份相关测试共 142 项全部通过，其中新增工具栏回归 22 项；全仓 analyze 无 error，保留 5 项既有 warning 和 SDK 弃用等 info，本次未新增 warning。修改的 Dart 文件均少于 500 行，`git diff --check` 通过。
