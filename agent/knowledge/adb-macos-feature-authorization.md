# AnyDeck macOS 功能入口授权

## 用户路径

2026-11-13：删除独立「macOS 权限」设置分类、搜索项、通用权限模型与专用 MethodChannel。macOS 与其他平台统一保留原 7 类设置，授权按功能就近处理。

| 功能 | 入口与授权行为 |
| --- | --- |
| 摄像头扩展 | Android 设备 → 控制 → 摄像头 →「用作 Mac 摄像头」；安装后等待批准时显示「打开系统设置」，待批准不重复安装 |
| 登录项 | 设置 → 常规 →「开机自启」；启用时注册登录项，需要批准时在当前行显示提示与系统设置入口 |
| iPhone USB 相机权限 | 开始 USB 投屏时检查并申请，沿用原流程 |
| Bluetooth / 通知 / 定位 | 沿用附近分享、连接提醒/消息转发、Wi-Fi「读取名称」的原功能入口 |
| 局域网 / 文件夹 | 由真实访问或系统文件选择器按需触发用户同意，不在设置中探测和集中申请 |

注册或打开系统设置都不等于已经授权。摄像头以真实扩展状态为准；登录项使用系统实际状态区分已启用、未开启、等待批准、当前不可用及读取失败。macOS 12 的旧 LaunchAgent 配置存在只说明已配置，不能作为系统批准结论。

## 设计与边界

- 摄像头复用 `anydeck/virtual_camera`：安装、停用和原有状态轮询保留，新增 `openSettings`。Dart 使用可取消且最多完成一次的调用等待器处理 void 结果，再重新查询状态，不把跳转响应解析成可用快照。
- 安装批准入口位于原 `VirtualCameraControls`；原可见控件的 1 秒状态轮询负责从系统设置返回后的状态更新。关闭弹窗停止轮询，继续保持既有全局摄像头共享的生命周期。
- 登录项复用 `any_deck/autostart`，增加 `status` / `openSettings`；新系统读取 SMAppService 状态。注册成功后可能仍是 `requiresApproval`，不能在异常或待批准时改写 LaunchAgent 绕过系统批准。
- 开机自启行使用独立 Widget 管理短期状态、按钮防重复及应用/窗口回焦监听。系统注册失败时不把偏好和广播提前写成成功，保留 `AppSettingsController` 原有持久化与跨窗口入口。
- 原生设置跳转按系统版本选择：摄像头扩展在 macOS 15+ 打开「登录项与扩展」，13/14 打开「隐私与安全性」；登录项在 macOS 13+ 打开登录项，12 打开用户与群组。打开失败回传错误供功能入口显示。
- 不在初始化、读取状态或回到前台时自动安装扩展、启用自启动、请求隐私权限或启动手机采集。不增加常驻后台权限轮询。
- 删除 `anydeck/macos_permissions` 及其页面、文案、原生注册、Xcode Sources 与测试。保留既有系统用途声明和实际功能的权限请求。

## 实现入口

- `lib/core/virtual_camera/virtual_camera_controller.dart`、`virtual_camera_state.dart` 与 `lib/features/control/widgets/virtual_camera_controls.dart`：扩展安装、批准和状态展示。
- `macos/Runner/VirtualCamera/VirtualCameraPlugin.swift`：摄像头功能自己的状态和系统设置跳转。
- `lib/app/settings/desktop_autostart_service.dart`、`app_settings_controller.dart` 与 `lib/features/overview/settings/autostart_setting_control.dart`：自启服务、偏好保存和批准 UI。
- `macos/Runner/AutoStartBridgeService.swift`：登录项注册、真实状态与系统设置跳转。
- `app_l10n_virtual_camera.dart`、`app_l10n_autostart.dart`：功能入口的中英文状态和错误文案。

## 验证与人工验收

自动化覆盖功能入口的待批准状态、跳转成功后回读、失败重试、防重复、销毁后迟到结果，以及设置导航与搜索不再显示独立权限页。Swift SDK typecheck 检查 macOS 版本可用性和通道注册；原生检查不进行真实安装或登录项注册。

人工验收使用合适签名的 AnyDeck：

1. 安装摄像头扩展后待批准时，从原功能入口打开系统设置；批准后返回，只有实际发现并就绪才允许共享。跳转失败、签名缺失、待重启时保留相应状态。
2. 开启自启后若系统要求批准，从自启行进入系统设置；批准或撤销后返回检查状态。注册失败不应显示为已启用，待批准时仍能取消。
3. 中英文、明暗主题和窄窗口布局下，状态与错误可读，按钮不重复执行；离开入口后不再更新已销毁界面。
4. 设置侧栏、窄屏下拉和搜索均没有「macOS 权限」分类；其他 7 类设置和跨窗口偏好同步保留。

自动测试不能代替不同 macOS 版本的设置链接实际落点、系统批准弹窗与正式签名摄像头扩展的验收。未授权时仍由 macOS 阻止相关能力。

### 本次验证记录

- Dart 共 65 项通过：摄像头 controller / Widget / 租约 23 项，自启 service / Widget 19 项，设置导航 / Workspace / Review 19 项，原 AppSettings 4 项。
- 受影响 Dart 文件定向 analyze 无问题。新旧摄像头原生测试脚本通过；新增激活状态测试覆盖旧设备可见但新安装仍待批准的优先级，登录项纯映射测试覆盖旧 LaunchAgent 配置保留取消入口。
- 摄像头与自启桥接在 arm64 / x86_64、macOS 12.0 deployment target 下 Swift SDK typecheck 通过；Xcode 工程 plutil lint 和 diff check 通过。
- 自启等待由 Provider 管理取消：即使原生状态查询或设置跳转不返回，销毁入口也会释放 timeout Timer，迟到回调不再发布状态。跨窗口收到自启广播只更新本地偏好，不重新注册系统登录项。
- 未启动 AnyDeck，未安装扩展、注册真实登录项或触发系统批准。

```bash
flutter --no-version-check test --no-pub \
  test/virtual_camera_test.dart test/virtual_camera_widget_test.dart \
  test/virtual_camera_preview_lease_test.dart \
  test/desktop_autostart_test.dart test/autostart_setting_control_test.dart \
  test/dashboard_shell_navigation_test.dart test/settings_workspace_test.dart \
  test/settings_review_test.dart test/app_settings_test.dart
bash script/test_virtual_camera_native.sh
plutil -lint macos/Runner.xcodeproj/project.pbxproj
git diff --check
```
