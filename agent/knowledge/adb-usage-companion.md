# 使用时长手机端与 ADB 最小闭环

## 范围与用户流程

- 桌面入口：Android 设备 → 应用 → 工具栏“使用时长”（柱状图按钮）。
- 首次点击“安装手机端”，安装内置 `assets/android/usage_companion.apk` 并打开可见入口。
- 手机端明确展示采集范围，用户开启 ADB 共享并在系统设置授权使用情况访问。
- 桌面点击同步后显示屏幕交互时长、App 前台累计、App 排行和系统实际统计区间。
- 无后台常驻服务、开机接收器、隐藏入口、网络权限或自动授予权限命令。
- 第一版按需读取 Android 已有统计；可能包含安装前系统保留的今日记录，不是从安装时开始独立持续采集。

## 分层与复用

| 层 | 文件/目录 | 职责 |
| --- | --- | --- |
| 手机 UI | `tool/usage_companion/src/com/adbmanage/companion/MainActivity.java` | 可见的共享开关、权限设置、手动预览 |
| 手机数据 | `UsageRepository.java` | UsageStatsManager 系统日桶查询、安装标识、原子保存最新快照 |
| 手机接口 | `UsageProvider.java` | 仅允许 Binder UID 2000 的 ADB shell 调用；逐次检查共享与权限 |
| 传输与缓存 | `lib/core/usage/` | ADB 同步、协议校验、最后快照缓存 |
| 页面状态 | `lib/features/apps/controller/usage_report_controller.dart` | 防重复、错误状态、生命周期处理 |
| 展示 | `lib/features/apps/widgets/usage_report_dialog.dart` | 双语、明暗主题、离线快照与虚拟列表 |

复用 `AdbService.shellArgs/run`、`AppManagementService.installApk`、`packagesProvider`、`AdbPackage` 和 `_AppNameCell`。
**禁止在使用时长链路重新获取图标、重新实现名称缓存，或复制 PackageIconHelper。** 未命中已有缓存时显示包名及原有占位图标，用户可使用应用页原有刷新功能补齐。
现有应用列表、DEBUG 标识、图标 helper、投屏链路与原生窗口通信均未改动。没有新的 Flutter 依赖。

## 统计口径

- `queryUsageStats(INTERVAL_DAILY, 手机今日零点, 手机当前时间)` 查询系统已有日桶。
- Android 官方允许扩展查询区间，因此保留各 App 的 `firstTimeStamp/lastTimeStamp`，不能标成严格自然日时长。
- `foregroundMs` 来自 `getTotalTimeInForeground()`；同一包多个日桶合并。App 累计可能重叠，不能作为手机总使用时长。
- Android 9+ 通过 `queryEventStats` 中的 `SCREEN_INTERACTIVE` 单独读取屏幕交互时长及其区间；Android 8 不调用该 API，显示“系统未提供”。
- 系统汇总可能存在延迟、受 ROM 口径影响，不承诺与健康使用手机页面完全一致。
- 无统计响应使用 `no_data`，不能等价显示为零使用。空 App 列表与缺失屏幕指标分别处理。
- 桌面按快照中的手机 UTC offset 显示时间；目前不是完整时区数据库换算，跨夏令时边界的历史显示留待后续完善。

参考：[UsageStatsManager](https://developer.android.com/reference/android/app/usage/UsageStatsManager)。

## ADB 协议与状态

1. `am get-current-user` 确认目标用户。
2. `pm path --user <id> com.adbmanage.companion` 检查目标用户是否已安装。
3. `content call --user <id> --uri content://com.adbmanage.companion.usage --method snapshot` 获取 Base64 JSON。
4. 解析并校验版本、时间范围、App 行、返回用户，再次确认当前用户未变化。
5. 桌面成功解析后覆盖最后快照，失败保留旧记录，并明确展示快照生成时间与非实时提示。

手机端 `ContentProvider.call` 自行检查调用 UID，不能只依赖 manifest `DUMP` 权限；鉴权后清除 Binder 调用身份，再以 App 自身权限读取数据。普通 App 无法调用数据接口。已获得 ADB 授权的电脑均属于本版的信任范围，不包含独立电脑配对系统。

`schemaVersion=1` 包含 `installationId`、`androidUserId`、`generatedAtMs`、`requestedStartMs`、实际统计区间、时区、可选屏幕指标及 App 数组。手机进程内使用共享锁协调手动预览与 Provider 并发写入；AtomicFile 保存私有文件 `files/usage_snapshot.json`。原始 JSON 上限 256 KiB，为 Base64/Bundle 的 Binder 传输预留空间。

错误码：`sharing_disabled`、`permission_required`、`user_locked`、`no_data`、`internal_error`。桌面还区分连接失败、未安装、协议错误、切换用户、安装失败与缓存读写失败。

桌面复用 SharedPreferences 保存 `usage.snapshot.v1.<ADB路由>`，只保留最新一份；不重复累计、不维护长历史。快照携带安装标识和 Android 用户。USB/Wi-Fi 路由变更不会自动合并；旧快照显示其原 Android 用户，后续长期存储需接入稳定设备身份。清除按钮仅清除电脑该路由的快照。

## 构建与安装

```bash
python3 script/build_usage_companion.py
```

- 无 Gradle/Maven 依赖，使用 Android SDK build-tools 36.0.0、android-36 和本机 JDK。
- 最低 Android 8（API 26），targetSdk 36；构建脚本支持 `ANDROID_SDK_ROOT` / `ANDROID_HOME` / `JAVA_HOME`。
- 开发签名位于忽略目录 `.build/usage_companion/development.keystore`，不可提交。
- APK 内置到 Flutter assets；源码变更后必须重新构建 APK 并与源码一起提交。
- 开发密钥丢失或其他机器重建会导致签名变化，不能覆盖安装；不要为解决签名问题自动卸载手机端。生产分发前需稳定签名管理。
- 使用 Java 原生平台 UI，资源中英文分离，适配明暗主题及系统栏空间。

## 验证与回归

```bash
flutter test test/usage_sync_test.dart test/usage_report_dialog_test.dart test/app_management_service_test.dart
flutter analyze
```

显式指定已授权测试设备才执行真实 ADB 测试（不自动开启权限）：

```bash
flutter test test/usage_sync_test.dart --dart-define=USAGE_ADB_DEVICE=<设备ID>
```

- 协议测试覆盖扩展日桶、缺失指标、空列表、未知版本、负时长、重复包、共享/权限拒绝、用户切换和缓存隔离。
- 弹窗测试覆盖中英文 × 明暗主题、离线禁用同步和复用缓存名称。
- 真实 ADB 测试读取手机 App → Dart 解析 → mock 持久化接口往返；不将真实使用记录写入仓库或日志。实际桌面插件持久化仍需启动桌面端后手工回归。
- 手工回归：关闭手机端共享 → 同步被拒绝；撤回使用权限 → 明确提示；拔线 → 失败且保留旧快照；重复同步 → 替换快照；切用户 → 不串读；未知 App → 原有占位图标；刷新图标 → 使用页复用更新后的缓存。
- 后续范围：精确自然日事件统计、长期离线历史、稳定设备身份、增量协议、位置功能及局域网同步。

## 本次验证记录（2026-09-12）

- 已在连接的小米 Android 16 / HyperOS 3 手机上安装并成功读取真实使用统计，首次返回 25 个 App，最终版本再次验证返回 26 个 App；具体使用数据不入库到仓库。
- 同步与现有 App 缓存回归共 11 项通过（含真实设备测试），弹窗 4 项通过。
- 全量 `flutter analyze` 报告 53 项：其中 `test/apps_tab_filter_test.dart` 的缺参及未定义测试符号为既有编译错误，其余为既有 warning/info；不扩展修改无关文件。
- 未启动 Flutter 桌面项目；原有 `prototype/` 未跟踪目录保持不变。
- 新增代码及测试独立 `dart analyze` 无问题。手机端截图已检查，并修复浅色主题下状态栏图标对比度。
