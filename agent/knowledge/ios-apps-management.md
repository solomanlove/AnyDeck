# iOS 应用筛选、收藏与图标管理

## 业务入口与交互

设备工作区的 iOS「应用」Tab 复用 Android 的 `DashboardTabLayout`、`DashboardSearchToolbar`、可排序表头和 `AppsAlphabetSidebar`。默认展示用户应用，提供用户应用、系统应用、全部和收藏四种分类。

- 搜索与分类取交集，支持名称、Bundle ID、中文全拼和拼音首字母，忽略大小写及首尾空格。
- 点击应用名称旁的星标添加或取消收藏；收藏页包含收藏的用户和系统应用。
- 表格展示名称、Bundle ID、版本和类型，显示筛选数/设备总数；名称和版本可切换升降序。
- 右侧 `# / A–Z` 根据当前筛选结果启用字母。中文按拼音首字母定位，其他字符归入 `#`；点击跳到当前排序中对应的第一行。
- 列表固定行高 56，使用 `ListView.builder`；窄窗口表格可水平滚动，字母栏保持可见。工具栏根据当前语言及字体测量换行，保留搜索清除按钮的空间。
- 保留 IPA 安装和用户应用卸载；系统应用卸载按钮禁用。安装选择、卸载确认和命令回调均绑定发起时的设备，切换设备后不误操作另一台手机。

## 实现分层

| 文件/模块 | 职责 |
| --- | --- |
| `features/ios/ios_apps_tab.dart` | 页面生命周期、设备操作确认与反馈 |
| `features/ios/controller/ios_apps_controller.dart` | UDID 隔离的应用流、图标请求取消、收藏和搜索历史 Provider |
| `features/ios/model/ios_apps_filter.dart` | 分类、搜索、拼音首字母纯数据处理 |
| `features/ios/widgets/ios_apps_toolbar.dart` | 共用搜索及分段 UI 的 iOS 配置 |
| `features/ios/widgets/ios_apps_table.dart` | 虚拟表格、排序与字母定位 |
| `core/ios/ios_command_service.dart` | `ios apps --all --udid=<UDID>` 及列表 JSON 解析 |
| `core/ios/ios_icon_service.dart`、`assets/ios/ios_icon_helper.py` | 图标缓存、可取消的 Python helper 调度与 SpringBoard 协议 |
| `features/ios/widgets/ios_app_icon_view.dart` | 图标渲染及缺失/损坏占位 |

应用解析接受数组、应用对象、Bundle ID 映射和外层容器；兼容四种 ID 字段。映射项缺少显式 ID 时，只有存在应用元数据才使用 key 作为 ID。识别到应用后停止递归，避免把 Entitlements、Extension 等嵌套对象误列为独立应用；日志对象跳过。系统分类依据 `ApplicationType/type`，不以 `com.apple` 前缀猜测。

## 状态与存储

- `iosAppsProvider(udid)` 是 autoDispose StreamProvider：先交付应用列表和已有内存图标，再交付本次图标结果；图标失败不隐藏应用列表。
- 手动刷新 invalidate 对应 UDID 的 Provider；退出或切换设备时取消图标请求，旧结果不回写新设备。
- 收藏复用 `AppFavoritesNotifier`，新增可配置存储 key；iOS 使用 `ios.apps.favoriteBundleIds.v1`，Android 原 key 保持不变。同一 Bundle ID 在多台 iPhone 上共用收藏。
- 搜索历史复用 `DashboardSearchHistoryNotifier`，key 为 `ios_apps_search_history`，最多 10 条，不混入 Android 的 DEBUG 快捷项。
- 本功能仅在主设备工作区使用，没有新窗口或新的全局主题/语言配置。文案复用共享 l10n，并新增中英文 `favoriteApps`。

## 图标请求与边界

图标功能承接原有待提交代码，使用 Python 标准库连接本机 `/var/run/usbmuxd`，通过配对记录启动 `com.apple.springboardservices`，发送 `getIconPNGData`。每批最多 30 个 Bundle ID，每批进程最多 15 秒；取消或超时时终止 helper。配对记录的 go-ios 子命令另有 5 秒超时。

- helper 作为 Flutter asset 发布，运行依赖主机的 `python3`，go-ios 路径复用项目工具解析逻辑。
- 只选择请求 UDID 对应的设备，不回退到第一台设备。socket 使用超时和完整帧读取，拒绝截断及异常长度响应。
- UDID 和 Bundle ID 在用于缓存路径前校验；只接受本批请求 ID 对应的预期输出路径。
- PNG 保存在临时目录 `ios_app_icons/<UDID>/`，先检查内存/磁盘缓存；真实图标不可用时显示主题适配占位。
- 当前 helper 路径依赖 Unix usbmuxd；Windows、Finder Wi-Fi 图标提取、不同 iOS 版本和配对环境尚未进行真机验证。缓存图标不随普通列表刷新强制重新提取。
- 本次不涉及 Android/HarmonyOS 设备命令或投屏链路。

## 自动验证与人工回归

自动验证包含：

1. 应用解析结构、日志过滤和嵌套元数据隔离。
2. 分类/搜索组合、拼音、收藏持久化及 Android 存储隔离。
3. Widget 下分类、收藏取消、搜索历史、窄窗口/暗色模式、系统应用卸载禁用。
4. 切换设备后的延迟响应隔离、离开页面取消图标、长列表字母跳转。
5. Python 的 socket 分片、截断及非法长度处理。

定向运行命令：

```bash
flutter test --no-pub test/ios_apps_tab_test.dart test/ios_command_service_test.dart
flutter test --no-pub test/dashboard_search_history_test.dart
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s test -p ios_icon_helper_test.py
```

本次 iOS Flutter 回归 11 项、共享搜索组件回归 5 项、Python 协议测试 4 项全部通过；涉及文件的定向 `flutter analyze --no-pub` 无问题。全仓库分析存在 41 条既有问题，包含 `test/apk_install_coordinator_test.dart` 三处 override 签名不匹配，未纳入本次修改。

未启动项目、未构建发布包、未进行 iPhone 真机验收。后续人工检查：两台设备切换与拔线、USB/Wi-Fi 应用枚举、图标缺失回退、签名 IPA 安装/卸载、中英文和明暗主题、收藏重启恢复，以及 Android 原应用页回归。
