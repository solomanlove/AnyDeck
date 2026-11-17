# AnyDeck 设备分组

## 使用路径

设备管理工具栏在搜索右侧提供“全部分组”入口，可选择 Android、Harmony、iOS 或自定义分组。默认平台组按设备的 `isIos` / `isHarmony` 属性自动计算，包含离线历史设备；AirPlay 临时设备按 iOS 参与平台筛选。

“管理分组”支持新建、重命名、删除自定义分组，以及勾选设备加入或移出分组。同一设备可加入多个自定义分组。默认平台组只读，删除自定义分组保留设备及设备数据。名称去除首尾空格，最多 40 个 Unicode code points，忽略大小写后不能与已有分组重名。

## 架构与数据

| 位置 | 职责 |
| --- | --- |
| `lib/core/device_groups/device_group.dart` | 不可变分组、平台判断、成员物理身份、名称与 JSON 校验 |
| `lib/core/device_groups/device_groups_controller.dart` | `deviceGroupsProvider`、串行 CRUD、成员身份补全 |
| `lib/core/device_groups/device_groups_store.dart` | SharedPreferences 单 JSON 快照读写 |
| `lib/features/devices/widgets/device_group_filter.dart` | 工具栏菜单、默认平台与自定义分组入口、读取失败重试 |
| `lib/features/devices/widgets/device_groups_dialog.dart` | 默认分组查看、自定义组管理与成员勾选 |
| `lib/features/devices/widgets/device_group_name_dialog.dart` | 复用数据层规则校验名称 |
| `lib/features/devices/widgets/device_list_filters.dart` | 搜索、分组与视图工具栏的宽度计算及窄屏换行 |
| `lib/features/devices/dashboard_devices_panel.dart` / `dashboard_devices_view.dart` | 筛选状态、注册表身份更新监听、设备墙与列表共同过滤 |
| `lib/app/l10n/tables/app_l10n_device_groups.dart` | 中英文分组文案 |

无新增依赖。自定义数据使用 `devices.groups.v1` 保存版本、分组 ID、名称与成员；默认三个平台组在内存中重建。现有设备标签、备注、注册表存储键均保留原语义。

## 身份与持久化

- 成员以 Android / Harmony / iOS 命名空间隔离，优先使用物理 `serial`，同时保留 `id` / `connections` 别名。iOS 使用稳定 UDID。
- 初次网络连接时注册表可能以 TCP 地址或 mDNS route 充当 `serial`；这些值按未知物理身份处理。真实硬件 serial 补全后，工作区监听触发 `synchronizeDevices` 升级已保存成员，使 USB / 无线通道切换保持归属。
- 已知物理 serial 的成员不以旧网络地址匹配其他设备，防止 IP 复用串组。含点的合法硬件序列号继续保留。
- 分组管理只列出注册表设备。仅 AirPlay 会话生成的临时设备缺少稳定物理身份，不保存为自定义成员；它仍参与默认 iOS 分组筛选。
- 更新串行执行，保存成功后才发布新快照。保存失败保留旧状态，弹窗显示本地化错误并释放忙碌状态，允许重试。
- 可解析快照中的坏条目被忽略，有效分组保留。读取异常或非法 JSON 保留 `AsyncError`，禁止基于空快照写盘；工具栏仍允许默认平台筛选，并提供“重新加载分组”。
- 默认平台、搜索、在线/离线三种条件共同决定结果。统计反映当前分组，搜索不改变统计；清除筛选同时清除分组、状态和搜索。切换视图保持筛选及批量勾选；删除当前自定义组后回到全部分组。

## 窗口、性能与主题边界

分组只由主窗口设备管理使用，投屏及其他子窗口不读写此配置，不新增 MethodChannel 广播。没有新增 ADB / HDC / iOS CLI、设备轮询、投屏会话或后台进程。

工具栏按实际语言、字号和分组控件宽度判断是否换行；小窗口下搜索和分组可上下全宽排列。组件使用项目 Theme、ColorScheme 和 `AppThemeSizes`，可见文案通过 `AppLocalizations` 读取。

## 验证与交接

```bash
flutter test --no-pub \
  test/device_groups_test.dart \
  test/device_group_toolbar_test.dart \
  test/device_group_workspace_test.dart \
  test/device_group_dialog_test.dart \
  test/device_list_filters_test.dart \
  test/dashboard_device_workspace_test.dart \
  test/dashboard_device_responsive_test.dart \
  test/dashboard_device_list_density_test.dart \
  test/device_list_context_menu_test.dart
flutter analyze --no-pub
git diff --check
```

自动测试覆盖默认三平台、离线/AirPlay 分类、分组 CRUD 与成员多归属、重启恢复、并发写、读取和保存失败、TCP / mDNS 占位身份升级、网络地址复用、中英文与明暗主题、放大字号与窄屏布局，以及真实 Dashboard 的筛选、视图、空态重置与设备操作回归。

本次 9 个测试文件共 91 项全部通过，`git diff --check` 通过。全仓静态分析无 error，5 条 warning 均位于未修改的既有模块；预览 Flutter SDK 同时提示现有 Material / Cupertino 导入弃用，不在本次变更中迁移。

不启动桌面项目或操作真机。人工验收可连接三平台设备，创建跨平台自定义组，重启应用确认保存，再执行 USB / 无线切换和设备插拔确认身份稳定；临时 AirPlay 会话的自定义归属不在支持范围内。
