# AnyDeck 设备系统版本排序

设备管理的列表视图支持点击“系统版本”表头：首次升序，再次降序，并显示方向图标。排序状态与设备墙共享，切换视图、搜索、分组及在线/离线筛选后继续保持。

## 实现与边界

- `lib/features/devices/model/device_system_version_sort.dart` 提供纯比较器 `DeviceSystemVersionSort.compare`，只使用当前列展示的 `RegisteredDevice.androidVersion`，不探测设备、不读取厂商 `customOs` 或额外 SDK 字段。
- 系统名称忽略大小写，同系统按点分版本数字比较，例如 `Android 9 < 10 < 17`、`iOS 15.8.9 < 15.8.10`。缺少的尾部零段视为相等，`18` 与 `18.0` 等价；相同版本的 API 和预览后缀数字作为次级比较。
- `HarmonyOS NEXT (API 23)` 只有 API 时，以 API 数字作可用排序依据，避免把 `(API` 误当系统名称。数字使用 `BigInt`，避免超长版本字段溢出。
- 版本缺失或纯系统名称无数字时，升序、降序都置于当前优先级的末尾。相同版本按设备 ID 稳定兜底。
- `dashboard_devices_view.dart` 保留在线设备优先、AirPlay 投屏设备优先，再应用系统版本顺序。跨系统先按系统名称比较；不同平台的 API 不作为统一版本高低。
- 表头复用 `_SortableHeaderCell`，增加固定列宽支持，保持设备名列的弹性布局。窄屏仍沿用系统版本内联展示策略，已选排序保持有效。

没有新增 Provider、持久化键、依赖、CLI 或窗口广播。文案沿用中英文系统版本表头，图标颜色沿用项目 Theme。投屏、设备身份、设备标签和批量勾选逻辑保持现有行为。

## 验证

```bash
flutter test --no-pub \
  test/device_system_version_sort_test.dart \
  test/device_system_version_sort_widget_test.dart \
  test/dashboard_device_list_density_test.dart \
  test/dashboard_device_responsive_test.dart \
  test/device_group_workspace_test.dart
flutter analyze --no-pub
git diff --check
```

单元测试验证三平台、数字分段、API、空值及升降序；真实 Dashboard Widget 测试验证表头点击和图标、在线优先、未知值置底、视图切换以及离线筛选，并覆盖中英文与明暗主题。布局回归覆盖原系统版本内容和窄屏展示。不启动桌面应用或操作真机。

本次 5 个测试文件共 45 项全部通过，`git diff --check` 通过。全仓静态分析无 error，5 条 warning 均来自未修改的既有模块；预览 Flutter SDK 的 Material / Cupertino 弃用提示沿用现有导入惯例，不在本次迁移。
