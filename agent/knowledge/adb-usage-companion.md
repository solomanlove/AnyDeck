# 手机使用统计、位置记录与 ADB 历史同步

## 范围与操作流程（v0.2.0）

桌面入口：Android 设备 → 应用 → 工具栏“使用时长”（柱状图按钮）。弹窗分别提供使用时长和位置历史。

1. 点击“安装手机端”，覆盖安装内置 `assets/android/usage_companion.apk` 并打开可见入口。
2. 使用统计：手机开启统计 ADB 共享，在系统设置授予使用情况访问权限；可额外勾选自动保存统计。
3. 定位：手机单独开启位置记录共享，点击“开始记录位置”，授予位置和通知权限，授权完成后再次点击开始。
4. 手机出现持续记录通知后可离线积累位置，通知或页面均可停止。桌面只拉取已有记录，不远程启动定位。
5. 桌面分别点击“同步使用时长”和“同步位置记录”，保存到电脑 SQLite；断开手机仍能查看。

两项共享和自动统计默认关闭，定位需显式启动。没有隐藏入口、开机接收器、自动授予权限、保活绕过或手机网络服务。已授权 ADB 的电脑属于信任范围，尚无独立电脑配对。

## 分层与复用

| 层 | 文件/目录 | 职责 |
| --- | --- | --- |
| 手机 UI | `MainActivity.java`、`LocationControls.java` | 可见授权、独立开关、预览、定位开始/停止 |
| 使用统计 | `UsageRepository.java`、`UsageArchiveJob.java` | 系统日桶查询、按需和系统周期调度保存 |
| 定位 | `LocationRecordingService.java` | LocationManager 与带通知的 location foreground service |
| 手机离线库 | `CompanionStore.java` | SQLite 两个流、递增编号、安装标识、分页 |
| 手机接口 | `UsageProvider.java` | 限 Binder UID 2000，查询前后检查共享及统计权限 |
| 桌面协议 | `lib/core/usage/companion_history.dart`、`usage_sync_service.dart` | 来源校验、分页恢复、安装和旧快照兼容 |
| 桌面数据库 | `lib/core/usage/companion_database.dart` | 工作 Isolate 内 SQLite 事务、游标、路由关联 |
| 页面状态 | `usage_report_controller.dart`、`usage_report_view_controller.dart` | 同步/迁移/清除、展示选择、地图打开及生命周期 |
| 展示 | `usage_report_dialog.dart`、`location_history_view.dart`、`location_trail_view.dart` | 双语报告、日期筛选、离线轨迹和位置列表 |

复用 `AdbService.shellArgs`、`AppManagementService.installApk`、`deviceRegistryProvider`、`packagesProvider`、`AdbPackage`、`_AppNameCell`、`webDebugServiceProvider` 及已有 sqlite3/path_provider 依赖。
**使用时长链路不重新获取图标、不复制 PackageIconHelper 或名称缓存。** 缓存未命中时显示包名和原有占位图标。未改动投屏、应用缓存逻辑或原生窗口通信。

## 采集与保留边界

### 使用统计

- `queryUsageStats(INTERVAL_DAILY, 手机今日零点, 手机当前时间)` 查询真实系统日桶，可包含安装前保留的今日记录。
- Android 可扩展查询区间，保留每项 `firstTimeStamp/lastTimeStamp`，不承诺严格自然日。
- `foregroundMs` 来自 `getTotalTimeInForeground()`；同包日桶合并。App 时间可能重叠，不作为手机总时长。
- Android 9+ 单独查询 `SCREEN_INTERACTIVE`；Android 8 显示系统未提供。
- 手动预览/桌面同步生成快照；额外启用自动统计后 JobScheduler 请求每 15 分钟保存，Doze/ROM 可推迟。
- Job 不跨开机持久化，重新打开手机端后按原有设置安排，不保证进程常驻。
- 快照保存到手机 SQLite 并保留私有 `files/usage_snapshot.json`，单条 JSON 上限 96 KiB。
- 桌面按查询起点分组，只展示每个查询日最后一份，不累加。同日末尾未采样时不是全天报告，不补采任意历史日期。
- 统计按快照手机 UTC offset 展示；系统延迟、跨夏令时和跨时区日界存在口径限制。

参考：[UsageStatsManager](https://developer.android.com/reference/android/app/usage/UsageStatsManager)、[JobInfo.setPeriodic](https://developer.android.com/reference/android/app/job/JobInfo.Builder#setPeriodic(long))。

### 定位

- 系统 NETWORK/GPS provider，不依赖 Google Play services；请求 5 分钟间隔、50 米最小位移。两个 provider 可分别回调，静止时可能没有新点；实际周期和功耗需目标 ROM 验证。
- 接受最近两分钟内系统回调，不用旧 lastKnownLocation 冒充当前位置。保存采集/接收时间、WGS84 坐标、精度、provider 和 mock 标志。
- 模拟位置明确标记，最后已知位置也显示模拟标识；拒绝越界坐标和无效时间。
- 用户在可见 Activity 启动 location foreground service，保持持续通知；不申请后台定位权限，不提供 ADB 启动记录接口。
- 停止按钮停止新采集，历史仍可同步；关闭位置共享同时停止采集并拒绝历史导出。手机私有历史仍保留。
- 进程被杀/手机重启后不自动恢复定位，需再次打开并点击开始；未做小米保活豁免或可靠性承诺。

参考：[location foreground service](https://developer.android.com/develop/background-work/services/fgs/service-types#location)、[定位运行时授权](https://developer.android.com/develop/sensors-and-location/location/permissions/runtime)、[LocationManager](https://developer.android.com/reference/android/location/LocationManager)。

### 保存与展示

- 手机每个流写入时裁剪超过 7 天或超过 10000 条的记录；停止写入期间不主动清理，导出不删除。
- 桌面库位于应用支持目录 `companion/history.sqlite`，使用 WAL 和 5 秒 busy timeout，沿用应用文件权限，无额外数据库加密。
- 当前来源展示最近 30 个查询日和最近 10000 个位置点；电脑入库历史目前不自动按天裁剪。
- 位置按电脑时区筛选，保留最后已知时间/精度/来源，明确为已同步历史。
- 离线轨迹是无底图示意，最多 1000 点；超过 30 分钟、模拟点和跨国际日期变更线不连线。
- 用户点击位置行地图按钮后，在默认浏览器打开 OpenStreetMap 坐标。无自动联网、内置地图瓦片或实时地图刷新。

## 协议、身份与事务

1. `am get-current-user` 确认用户，调用 `identity` 获取 schemaVersion 2、安装实例和 Android 用户。
2. 使用统计先调用兼容的 `snapshot` 生成快照；位置直接读取已保存的点。
3. 按电脑 `(installationId, androidUserId, kind)` 游标调用 `usage_history` / `location_history`。
4. `--arg <after>:<upperBound>`，首轮上界 0；返回固定上界、`firstAvailableId`、`nextCursor`、`hasMore` 和 records，每页最多 100 行及约 128 KiB 原始 JSON。
5. 校验版本、来源、编号递增、游标、固定上界和内容，再次确认用户后入库。
6. 记录和游标同一 SQLite 事务提交，重复页 `INSERT OR IGNORE`；中断从已提交游标恢复。一次最多 120 页，未完成提示再次同步。

调用示例（设备已授权，权限在手机端开启）：

```bash
adb -s <设备ID> shell content call --user <用户ID> --uri content://com.adbmanage.companion.usage --method identity
adb -s <设备ID> shell content call --user <用户ID> --uri content://com.adbmanage.companion.usage --method location_history --arg 0:0
```

外层仍是 `Bundle[{payload=<Base64 JSON>}]`。Provider 显式检查 UID 2000，再清除 Binder 身份，以 App 自身权限读取。普通 App 不可调用。

USB/Wi-Fi 路由优先复用注册表 serial；最终按安装实例和用户隔离，不同路由导入同一实例不会重复入库。重装形成新来源，旧来源数据不覆盖；页面仅显示路由最新关联来源，尚无旧安装实例选择器。

旧 SharedPreferences 快照首次打开迁移为编号 0，不推进游标；先完成迁移再同步/清除，避免清除后回写旧数据。清除电脑历史同时删除当前来源的记录、游标和路由别名；手机数据保留，可再次导入。手机保留期造成缺口时持久化提示。

错误包括 `sharing_disabled`、`permission_required`、`user_locked`、`no_data`、`cursor_invalid`、`internal_error`，以及桌面连接、用户变化、版本、解析与读写错误。没有统计响应不等于零使用。

## 构建与验证

```bash
python3 script/build_usage_companion.py
flutter test --no-pub test/companion_history_test.dart test/usage_sync_test.dart test/usage_report_dialog_test.dart test/app_management_service_test.dart
flutter analyze --no-pub
```

- 无 Gradle/Maven 依赖，使用 SDK build-tools 36.0.0、android-36 和本机 JDK，minSdk 26、targetSdk 36。
- 支持 `ANDROID_SDK_ROOT` / `ANDROID_HOME` / `JAVA_HOME`。开发密钥在忽略目录 `.build/usage_companion/development.keystore`，不提交。
- 源码变更须重建并提交内置 APK。密钥丢失或其他机器重建可能签名不同，不自动卸载处理冲突；生产需稳定签名。
- 协议测试覆盖统计口径、拒绝授权、来源变化、越界坐标及非法游标。
- 实体 SQLite 测试覆盖重开回读、重复页、路由合并、来源隔离、强制游标写入失败整页回滚、断线恢复、保留期缺口及旧快照迁移。
- 弹窗测试覆盖中英文 × 明暗主题、复用 App 名称、离线同步禁用、模拟标识和日期筛选。

真机集成默认跳过；显式指定设备且手机已有非模拟位置时执行。不会自动授权/开始定位，不输出真实坐标或包名到日志与仓库：

```bash
flutter test --no-pub test/companion_history_test.dart --dart-define=USAGE_ADB_DEVICE=<设备ID> --dart-define=REQUIRE_REAL_LOCATION=true
```

该测试覆盖手机真实统计/位置 → ADB → 实体 SQLite → 重开回读。还需真机验证首次定位、关共享、撤权限、停止通知、Doze、长时间离线和重启行为。

## 验证记录（2026-09-12）

- v0.1 历史证据：此前在小米 Android 16 / HyperOS 3 读取真实统计，最终返回 26 个 App；当时没有定位与历史库。
- v0.2 APK 已构建。本轮 ADB 列表为空，未安装新版，也未验证真实定位和新增后台调度。测试坐标不能作为真实采集证据。
- 本次 21 项定向测试通过，2 项真机测试因设备未连接跳过；新增代码及相关测试的定向 `dart analyze` 无问题。
- 全量 `flutter analyze --no-pub` 仍报告 53 项既有问题，其中 `test/apps_tab_filter_test.dart` 有 27 个缺参/未定义符号错误；未扩大范围修复无关基线。
- 未启动 Flutter 桌面项目，`prototype/` 未跟踪目录保持不变。

后续范围：真机长期采样验证、完整自然日统计、内置地图底图、电脑历史保留策略、局域网同步。
