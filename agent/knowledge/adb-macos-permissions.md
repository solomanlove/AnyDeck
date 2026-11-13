# AnyDeck macOS 权限管理

## 需求与入口

2026-11-13：设置新增「macOS 权限」分类，集中展示每项权限的用途、系统授权状态，并为尚未授权的能力提供申请或系统设置入口。此分类只在 macOS 展示，参与既有设置搜索与宽窄分类导航。

权限申请由用户逐项触发；进入页面、搜索或刷新状态均不申请授权，不启动摄像头、设备发现、广播、文件夹扫描或文件传输。

## 权限与状态边界

| 权限 | 用途 | 查询和操作 |
| --- | --- | --- |
| 局域网 | 无线设备连接、LAN 设备共享与文件互传、AirPlay / DLNA 接收 | 公开 API 无可靠授权查询，显示「在系统设置中查看」；macOS 15 以下无需独立授权 |
| Bluetooth | 附近设备发现与互传 | 只读 `CBManager.authorization`；首次申请才创建 manager，不扫描或广播 |
| 定位服务 | 读取 Wi-Fi 名称、指定 Wi-Fi 自动共享 | 查询服务开关和 authorizationStatus；首次申请使用 When In Use，不读取坐标 |
| 相机 | 通过 AVFoundation 采集 iPhone USB 屏幕 | 只读 video authorization；首次申请不启动采集 |
| 通知 | 连接提醒、消息转发与来件提醒 | 查询 UNUserNotificationCenter；首次申请 alert / sound / badge，不发送测试通知 |
| 文件和文件夹 | 保存截图、录像和接收文件 | 不遍历受保护目录探测，显示需在系统设置查看，并提供 Files and Folders 入口 |
| 摄像头扩展 | 将 Android 摄像头提供给 Mac 视频应用 | 复用既有摄像头扩展状态，不自动安装或启用；默认构建不具备安装能力时显示当前不可用 |
| 登录项 | 登录 macOS 后自动启动 AnyDeck | 只读 SMAppService 状态；跳转系统登录项设置，不改变原自启动开关 |

系统读取失败、缺失字段或未知的新状态统一保留为「未知」，不解释为已授权或尚未申请。受系统限制与系统全局服务关闭分别展示。系统设置打开成功不表示授权成功，始终重新查询。

局域网和文件夹访问没有单一可靠的公开授权枚举，因此不调用私有 TCC API、不读 TCC 数据库、不发起网络/文件探测，也不根据磁盘可写或网络连通推断授权。正常 Android 投屏控制不新增屏幕录制、辅助功能、输入监控、麦克风或 Full Disk Access 申请。

## 架构与生命周期

- `lib/core/permissions/mac_permission.dart`：稳定权限 ID、授权状态和短期页面状态。
- `mac_permissions_service.dart`：`anydeck/macos_permissions` MethodChannel；`readAll` 返回权限 ID 到状态字符串的 Map，`request` / `openSettings` 使用 `{permission: ID}` 白名单参数。
- `mac_permissions_controller.dart`：autoDispose Notifier，串行用户动作、版本号隔离迟到刷新、保留错误和未知状态；不新增 Preferences。
- `lib/features/overview/settings/macos_permissions_page.dart` 与 `macos_permission_row.dart`：页面生命周期、主题和自适应布局；不在 Widget 内实现权限业务逻辑。
- `macos/Runner/MacosPermissionBridgeService.swift` 与 `MacosPermissionStatus.swift`：公开 macOS API 的状态读取、显式授权和系统设置跳转；只注册到设置所在的主 Engine。
- `app_l10n_macos_permissions.dart`：独立中英文文案表，与既有 locale/theme Provider 共享；不新增语言或跨 Engine 同步协议。

页面初次挂载、App 恢复或窗口重新聚焦、手动刷新和动作完成后读取状态，不常驻轮询。授权动作有防重复与超时，页面销毁后不写已释放 Provider；迟到读取不会覆盖更新的系统状态。

## 验证与交接

自动检查覆盖 service 通信与异常、controller 并发和销毁、Widget 的按钮分流/回焦刷新/中英文/明暗/窄窗口，以及既有设置分类与搜索回归。原生使用 SDK typecheck 和无权限副作用的状态映射测试验证，不启动 AnyDeck，不弹系统授权窗。

手工验收使用实际签名的 AnyDeck：

1. 进入设置，确认读取状态不弹授权框；首次点击相机、Bluetooth、定位或通知的「申请授权」，确认只请求对应权限。
2. 拒绝后刷新，确认显示拒绝并提供系统设置；系统限制/关闭定位服务时不反复申请。
3. 在系统设置撤销或开启权限后切回 AnyDeck，确认页面刷新；重复点击和未完成系统弹窗期间不重复发起请求。
4. 检查局域网、文件夹权限的手工查看提示；不应根据其他能力已授权而显示已授权。
5. 在支持的 macOS 版本检查系统设置跳转；Camera Extension 不可用时不触发安装，自启动设置入口不自动注册登录项。
6. Windows / Linux 不显示 macOS 分类，其余设置分类、搜索、保存、主题和语言切换正常。

真实系统提示、权限撤销、系统设置链接在不同 macOS 版本的落点，以及有效签名摄像头扩展的系统批准，需要上述人工验收；自动测试不能代替。

### 本次自动验证结果

- 42 项 Dart 定向测试通过：service 4 项、controller 6 项、权限 Widget 与实际 Dashboard / 设置回归 32 项。
- 新增与修改的权限 Dart 文件、Widget 和测试定向 analyze 无问题。全量 `flutter analyze --no-pub` 无 error，但报告 38 项既有 warning / info 并返回非零；报告位置均为本次未修改的文件，不在本需求中顺带清理。
- 新原生桥接与 VirtualCamera 接入在 `arm64` / `x86_64`、macOS 12.0 deployment target 下 SDK typecheck 通过；原生纯映射与一次性回调测试 4 组通过。Xcode 工程 `plutil -lint` 和 `git diff --check` 通过。
- 摄像头扩展批准入口按 macOS 15 分界选择登录项与扩展 / 隐私与安全性；登录项按 macOS 13 分界选择新设置 / 旧用户与群组面板。扩展状态表示当前设备可用性，不代表包内扩展版本已经完成真实验收。
- 未启动桌面 App，未操作真实系统授权。未改变设备连接、投屏采集、自启动设置值或现有通知开关。

```bash
flutter --no-version-check test --no-pub \
  test/mac_permissions_service_test.dart test/mac_permissions_controller_test.dart \
  test/macos_permissions_widget_test.dart test/dashboard_shell_navigation_test.dart \
  test/settings_workspace_test.dart test/settings_review_test.dart
xcrun swiftc -target arm64-apple-macosx12.0 \
  macos/Runner/MacosPermissionStatus.swift \
  macos/PermissionTests/MacosPermissionStatusTests.swift \
  -o /tmp/anydeck-macos-permission-status-tests
/tmp/anydeck-macos-permission-status-tests
git diff --check
```
