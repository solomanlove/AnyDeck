# 应用权限分类与批量撤销

## 需求与入口

应用详情的「权限」Tab 和应用列表的权限管理弹窗共用 `AppPermissionsPanel`。支持搜索、全部 / 动态 / 静态 / 类型未知筛选及数量统计。动态权限提供开关；静态、未知及系统或策略固定权限只读。

「撤销所有权限」经确认后作用于本应用所有已授权的动态权限，搜索和分类不限制撤销范围。特殊访问（如悬浮窗、所有文件访问）不属于本次批量撤销范围，不承诺恢复应用的初始权限状态。

## 实现与数据来源

- `lib/features/apps/widgets/app_permissions_panel.dart`：共享 UI、确认弹窗、部分失败明细；采用主题颜色及中英文本地化，列表按需构建。
- `lib/core/apps/app_permission_controller.dart`：按 `(deviceId, packageName)` 隔离的 autoDispose Notifier。同一 Isolate 内的两处入口共享数据及操作锁，确认期间也禁止重复操作，执行期间通过 keepAlive 保留锁，避免关闭重开面板产生并发命令；查询、修改、异常回收与 UI 分离。
- `lib/core/apps/app_permission_service.dart`：复用 `AdbService.shellArgs`，元数据命令 10 秒、用户查询及权限修改 8 秒超时。批量命令串行执行，不启动独立常驻进程。
- `lib/core/apps/app_permission_parser.dart`：解析 `dumpsys package` 的 requested、install、当前 User 的 runtime 区块；以区块缩进隔离组件和其他用户数据。识别 `SYSTEM_FIXED` / `POLICY_FIXED` 标志。
- `lib/core/apps/adb_app_permission.dart`：权限类型可信状态、固定标志和可操作性。

读取 `pm list permissions -f` 中设备实际的 `protectionLevel`，补充分配在 requested 区块但尚无授权记录的权限类型，支持 Android 新增及厂商权限。`dangerous` 归为动态，其他已识别类型在此归为静态；未知权限单列只读。类型查询失败时仍保留 dump 中已确认的 runtime/install 分类。旧系统在 install 区块授予的权限在此保持静态只读。

## 命令与一致性

```bash
adb -s DEVICE shell am get-current-user
adb -s DEVICE shell dumpsys package PACKAGE
adb -s DEVICE shell pm list permissions -f
adb -s DEVICE shell pm grant --user USER_ID PACKAGE PERMISSION
adb -s DEVICE shell pm revoke --user USER_ID PACKAGE PERMISSION
```

一次操作固定当前加载的 `USER_ID`，批量操作的读取、修改与回读均使用该用户。用户解析失败会报错，禁止默默退回 user 0。切换设备的前台用户后需刷新面板。

单项操作也回读设备数据，不根据目标开关值伪造结果。批量撤销逐项记录异常，继续处理其余权限，再按回读结果统计成功与失败；命令 exitCode 为 0 但权限仍授予时不计成功。权限组联动撤销以最终状态为准。无法回读时显示错误并禁止继续使用旧状态操作，可通过刷新恢复。

主/子窗口本地化复用全局资源；没有新增 MethodChannel、插件或持久化设置。不同 Isolate 的面板通过刷新读取设备状态。

## 回归验证

自动验证命令：

```bash
flutter test --no-pub test/app_permission_parser_test.dart test/app_permission_operations_test.dart test/app_permissions_panel_test.dart
flutter analyze --no-pub
```

2026-09-11 验证结果：12 项测试通过；全仓静态分析无 error，本次代码无新增诊断，全仓仍有 27 条既有 warning / info。

测试使用 Fake ADB，不操作真实设备，覆盖：当前用户和其他用户隔离、旧系统安装权限、厂商动态权限、未知类型、元数据查询失败、固定权限、部分撤销失败、命令成功但状态未改变、无可撤销权限、用户查询失败、确认取消及重复操作拦截、断线后刷新恢复，以及中英文明暗主题下的 492px 窄面板。Widget 测试验证静态筛选没有开关，且筛选后批量撤销仍覆盖隐藏的动态权限。

待真机回归：Android 6.0+ 的授权与撤销、Android 13+ 通知和媒体权限、厂商 ROM / 企业策略、多用户切换、应用被卸载或设备断开，以及详情页与弹窗反复打开后的状态刷新。未启动项目或执行真机权限修改。

## 参考

- [Android 权限分类](https://developer.android.com/guide/topics/permissions/overview)
- [Android ADB 命令](https://developer.android.com/tools/adb)
