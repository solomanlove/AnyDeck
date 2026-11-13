# AnyDeck macOS 权限管理

## 需求与入口

2026-11-13：设置新增「macOS 权限」分类，最终保留摄像头扩展、登录项 2 项可能需要手动批准的能力，展示用途、系统状态和系统设置入口。此分类只在 macOS 展示，参与既有设置搜索与宽窄分类导航。

本页仅查询状态和打开系统设置；进入页面、搜索或刷新状态均不申请授权，不启动摄像头、设备发现、广播、文件夹扫描或文件传输。

## 权限与状态边界

| 权限 | 用途 | 查询和操作 |
| --- | --- | --- |
| 摄像头扩展 | 将 Android 摄像头提供给 Mac 视频应用 | 复用既有摄像头扩展状态，不自动安装或启用；默认构建不具备安装能力时显示当前不可用 |
| 登录项 | 登录 macOS 后自动启动 AnyDeck | 只读 SMAppService 状态；跳转系统登录项设置，不改变原自启动开关 |

系统读取失败、缺失字段或未知的新状态统一保留为「未知」，不解释为已授权或尚未申请。受系统限制与系统全局服务关闭分别展示。系统设置打开成功不表示授权成功，始终重新查询。

局域网和文件夹访问由实际使用触发系统授权，按用户要求不再列入权限页或设置搜索。没有单一可靠的公开授权枚举，因此不调用私有 TCC API、不读 TCC 数据库、不发起网络/文件探测，也不根据磁盘可写或网络连通推断授权。正常 Android 投屏控制不新增屏幕录制、辅助功能、输入监控、麦克风或 Full Disk Access 申请。

## 架构与生命周期

- `lib/core/permissions/mac_permission.dart`：稳定权限 ID、授权状态和短期页面状态。
- `mac_permissions_service.dart`：`anydeck/macos_permissions` MethodChannel；`readAll` 返回权限 ID 到状态字符串的 Map，`openSettings` 使用 `{permission: ID}` 白名单参数。管理页不再提供重复申请接口。
- `mac_permissions_controller.dart`：autoDispose Notifier，串行用户动作、版本号隔离迟到刷新、保留错误和未知状态；不新增 Preferences。
- `lib/features/overview/settings/macos_permissions_page.dart` 与 `macos_permission_row.dart`：页面生命周期、主题和自适应布局；不在 Widget 内实现权限业务逻辑。
- `macos/Runner/MacosPermissionBridgeService.swift` 与 `MacosPermissionStatus.swift`：公开 macOS API 的状态读取和系统设置跳转；只注册到设置所在的主 Engine。
- `app_l10n_macos_permissions.dart`：独立中英文文案表，与既有 locale/theme Provider 共享；不新增语言或跨 Engine 同步协议。

页面初次挂载、App 恢复或窗口重新聚焦、手动刷新和动作完成后读取状态，不常驻轮询。设置跳转有防重复与超时，页面销毁后不写已释放 Provider；迟到读取不会覆盖更新的系统状态。

## 验证与交接

自动检查覆盖 service 通信与异常、controller 并发和销毁、Widget 的设置跳转/回焦刷新/中英文/明暗/窄窗口，以及既有设置分类与搜索回归。原生使用 SDK typecheck 和无权限副作用的状态映射测试验证，不启动 AnyDeck，不弹系统授权窗。

手工验收使用实际签名的 AnyDeck：

1. 进入设置，确认只列出摄像头扩展、登录项；读取状态不弹授权框，按钮只打开对应系统设置。
2. 系统需要手动批准时，确认显示未授权并可打开系统设置；扩展不可用时不尝试激活。
3. 在系统设置撤销或开启权限后切回 AnyDeck，确认页面刷新；重复点击和未完成系统弹窗期间不重复发起请求。
4. 检查页面及设置搜索不显示局域网、文件夹、Bluetooth、定位、相机或通知项；相关功能区原有按需申请仍有效。
5. 在支持的 macOS 版本检查系统设置跳转；Camera Extension 不可用时不触发安装，自启动设置入口不自动注册登录项。
6. Windows / Linux 不显示 macOS 分类，其余设置分类、搜索、保存、主题和语言切换正常。

真实系统提示、权限撤销、系统设置链接在不同 macOS 版本的落点，以及有效签名摄像头扩展的系统批准，需要上述人工验收；自动测试不能代替。

### 初版自动验证结果

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

## 2026-11-13 自动触发授权项移除

用户要求可以在实际操作中自动申请的权限无需在管理页列出。本次删除 `localNetwork` / `files` 的页面模型、文案、原生只读占位与设置跳转白名单，页面保留 Bluetooth、定位、相机、通知、摄像头扩展、登录项。页面与搜索目录继续共用同一份权限枚举，不各自过滤。

这里的「自动」指 macOS 按实际使用触发申请，仍需用户确认，不代表静默获取授权。网络和文件功能的用途声明、连接、保存目录与系统选择器逻辑保留。已拒绝的访问仍受系统权限限制，不会因隐藏管理页条目而重新获准。

- [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)：没有通用 Local Network 状态查询或显式申请 API，符合条件的真实网络操作触发系统提示。
- [Apple WWDC23 隐私说明](https://developer.apple.com/videos/play/wwdc2023/10053/?time=1521)：目录访问由系统管理，Open/Save panel 的用户选择可提供对应资源的访问同意；不能将某个目录可访问解释为所有文件夹已授权。

本次调整验证：24 项权限 service / controller / Widget 测试及 19 项 Dashboard / 设置回归共 43 项通过；新增中英文页面和搜索不显示移除项的断言，并验证桥接忽略旧占位字段。定向 Dart analyze、macOS 12 target 的原生 SDK typecheck、4 组原生状态映射测试与 `git diff --check` 均通过。未启动 AnyDeck 或触发真实权限请求。

## 2026-11-13 仅保留需要手动批准的能力

继续按用户要求收口：从管理页和搜索移除 Bluetooth、相机、通知、定位；页面最终只显示摄像头扩展和登录项。前 3 项在功能使用时触发申请，定位在 Wi-Fi 信息区已有「读取名称」申请及拒绝后的设置跳转入口，不重复设置。

| 已移除项 | 实际功能入口 |
| --- | --- |
| Bluetooth | 附近分享 helper 创建 CoreBluetooth manager 后由系统申请 |
| 相机 | iPhone USB 投屏 `IosUsbCapturePlugin.start` 检查状态并 requestAccess |
| 通知 | 设备连接提醒及开启手机消息转发时 requestAuthorization |
| 定位 | Wi-Fi 信息区域「读取名称」→ requestWifiAccess → When In Use；拒绝时打开系统定位设置 |

保留的能力仍有单独的人工批准阶段：摄像头扩展在安装请求后可进入 `needsApproval`；登录项在启用自启动、完成注册后仍可能是 `requiresApproval`，需要在系统设置操作。开启自启和安装扩展均沿用原功能入口，权限页不代为启用。

同步删除权限管理专用的 Dart/native `request` 方法、4 类普通权限的重复状态映射和 manager 初始化，只保留 `readAll` / `openSettings`。原功能区、系统用途声明、投屏、分享和通知服务没有改动；页面不发起权限申请。

官方参考：[Camera Extension 批准回调](https://developer.apple.com/documentation/systemextensions/ossystemextensionrequestdelegate)、[SMAppService 审批状态](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/enabled)。

本轮验证：9 项 service / controller 测试和 33 项 Widget / Dashboard / 设置回归共 42 项通过；断言只保留 2 项、所有旧字段被忽略、自动申请项无法从权限目录检索，以及设置跳转的错误、防重复、状态刷新与销毁边界。定向 Dart analyze、4 组原生测试、arm64 / x86_64 macOS 12.0 target 的 Swift SDK typecheck 和 `git diff --check` 均通过。未启动 AnyDeck，未请求真实系统授权。
