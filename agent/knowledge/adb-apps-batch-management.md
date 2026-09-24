# 应用多选与批量管理机制 (App Batch Management)

## 需求背景
在 AnyDeck 应用管理（`AppsTab`）中，用户需要对已安装应用进行多选以及批量化运维，包括：
1. **批量导出包 (Batch Export APK)**：将选中的多个应用安装包导出至宿主机指定文件夹中；
2. **批量卸载包 (Batch Uninstall)**：二次确认后批量将选中的应用从 Android / HarmonyOS 设备中彻底移除；
3. **批量清除数据 (Batch Clear Data)**：二次确认后重置选中的应用数据（缓存、配置与登录态）；
4. **批量冻结应用 (Batch Freeze / 停用)**：二次确认后将选中的应用通过 `disable-user` 或 `bm disable` 停用；同时提供**批量解冻 (Batch Unfreeze / 启用)** 以便随时恢复应用可用状态。

## 架构与组件设计

### 1. 多选状态与交互流
- **状态维持**：
  在 `_AppsTabState` 中维护 `final Set<String> _checkedPackages = <String>{};`。
- **表格视图 (Table View)**：
  - `_PackageTableHeader`：首列增加固定宽度的全选 Checkbox（支持全选、反选、部分选中的三态 `tristate: true`）；
  - `_PackageTableRow`：首列增加 Checkbox，行点击选中背景与高亮，支持双击查看详情与单击勾选操作。
- **网格视图 (Grid View)**：
  - `_PackageGridItem`：在卡片左上角浮动显示微型 Checkbox，在卡片 Hover、项已被勾选或存在勾选应用时自动展现，支持便捷多选。

### 2. 批量操作工具栏 (`_AppsBatchActionsToolbar`)
位于 `lib/features/apps/dashboard_apps_batch_actions.dart`，当 `_checkedPackages.isNotEmpty` 时在搜索栏与应用列表之间动态展开：
- 显示勾选数量（`已选择 X 个应用`）；
- 快捷操作：“全选”与“取消全选”；
- 批量动作按钮：
  - **批量导出包**：调用宿主机原生文件夹选择器，并发/逐个拉取 APK；
  - **批量卸载包**：高亮危险色按钮，确认后静默卸载并自动刷新应用列表；
  - **批量清除数据**：清除应用存储；
  - **批量冻结 / 批量解冻**：批量修改应用状态，并在完成后自动更新本地应用缓存状态；
  - **右侧取消按钮**：一键清空选中状态。

### 3. 底层命令实现机制

| 操作 | Android 底层命令 | HarmonyOS 底层命令 | 宿主机/本地动作 |
| --- | --- | --- | --- |
| 导出包 | `pm path <pkg>` -> `adb -s <id> pull <remotePath> <localSavePath>` | 暂仅支持 Android APK 提取 | 文件重命名为 `<displayName>_v<version>.apk` 并存储 |
| 卸载 | `adb -s <id> uninstall <pkg>` | `hdc -t <id> shell bm uninstall -n <pkg>` | 卸载成功后触发 `refreshAllPackagesWithIcons` |
| 清除数据 | `adb -s <id> shell pm clear <pkg>` | `hdc -t <id> shell bm clean -n <pkg> -d` | 清空 `/data/data/<pkg>` 及 cache |
| 冻结 (停用) | `adb -s <id> shell pm disable-user --user 0 <pkg>` | `hdc -t <id> shell bm disable -n <pkg>` | 无需 root 权限停用应用 |
| 解冻 (启用) | `adb -s <id> shell pm enable <pkg>` | `hdc -t <id> shell bm enable -n <pkg>` | 恢复应用可执行状态 |

### 4. 进度反馈与用户体验
- 执行批量任务时，不再使用阻断全局视窗的全局 `showDialog`，而是通过 `ValueNotifier<_BatchProgressState?>` 驱动在当前应用管理 Tab 的 `body: Stack` 中浮层展示 `_AppsBatchProgressCard`；
- 浮层遮罩仅覆盖当前应用 Tab 区域，左侧主导航栏（主页、控制、应用、进程管理等）保持可见且不受阻断；
- 空闲时通过 `IgnorePointer(ignoring: progress == null)` 实现完全点击穿透，激活时线性进度条、当前正在处理的项名与序号（如 `32/51: 小米社区`）平滑更新；
- 处理完成后自动隐藏浮层，并汇总成功与失败数量通过 `_showSnack` 给出明确反馈。

### 5. 约束与边界
- 所有新增 Dart 类与重构文件均控制在 500 行以内；
- 多语言在 `app_l10n_apps_files_logcat.dart` 中同步补齐中英文双语字典；
- 离线设备或未连接时，批量操作按钮自动灰显禁用。
