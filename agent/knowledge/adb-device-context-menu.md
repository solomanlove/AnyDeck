# AnyDeck 设备列表常用操作右键菜单

## 需求与使用路径

2026-11-06：设备管理页支持右键点击设备行，高亮该行并显示常用功能。右键操作不进入设备详情、不修改 Checkbox 批量勾选，也不切换全局设备选择。

| 菜单项 | 行为 | 可用范围 |
| --- | --- | --- |
| 截图 | 截取当前屏幕，保存到设置目录并尝试复制图片到系统剪贴板，反馈保存路径 | 在线 Android / HarmonyOS；有 go-ios 连接的 iOS |
| 投屏 | 复用已有独立投屏入口；有 AirPlay 会话时打开对应窗口 | 在线 Android / HarmonyOS；USB iOS；已有 AirPlay 会话 |
| 设备信息 | 打开目标设备 `overview` Route | 包含离线历史设备 |
| 应用 | 打开目标设备 `apps` Route | 有设备连接 |
| 文件 | 打开目标设备 `files` Route | 有设备连接 |
| 终端调试 | 打开目标设备 `terminal` Route | 在线 Android / HarmonyOS，iOS 隐藏 |
| 编辑设备信息 | 复用设备名称、标签、备注编辑 Dialog | 包含离线历史设备 |

纯 AirPlay 虚拟设备没有 go-ios UDID，仅展示投屏入口。匹配到历史 iOS 行的 AirPlay LIVE 不代表 go-ios 已在线：缺少 USB / network 连接时，截图、应用和文件仍禁用。

## 实现分层

- `lib/features/devices/model/device_context_action.dart`：菜单动作、既有 l10n key、工具 slug 以及平台/在线能力策略。
- `lib/features/devices/dashboard_devices_context_menu.dart`：右键定位、菜单样式、当前设备回读和执行互斥；颜色及圆角使用 Theme / `AppThemeSizes`，长文案允许换行。
- `lib/features/devices/dashboard_devices_panel.dart`：维护页面局部右键高亮和操作状态，避免更改主窗口 Route 所拥有的全局设备选择。
- `lib/features/devices/dashboard_devices_rows.dart`：列表行接入右键，耗时操作期间在目标行显示进度指示。
- `lib/features/devices/dashboard_devices_actions.dart`：复用截图、投屏和编辑入口，导航统一使用 `AppRouteNames.deviceTool` 与既有 slug。
- `lib/features/control/widget/device_capture_actions.dart`：共享截图流程补齐 iOS 分流与双语成功提示，Android / HarmonyOS 继续走既有后端。

## 关键流程与边界

1. 右键捕获行 ID，更新局部高亮，按平台能力构建菜单。原有行内按钮、单击进入概览和 Checkbox 批量操作继续工作。
2. 用户选择动作后，重新合并当前注册表与 AirPlay 会话，按同一行 ID 查找设备并复查能力。设备已经删除、断线或对应会话停止时，不使用旧快照执行。
3. 耗时操作显示进度并拦截重复右键；异常通过已有 Toast 展示，finally 释放状态。
4. 截图按平台调用 `AdbService.captureScreenshot`、`HdcService.captureScreenshot` 或 `IosCommandService.captureScreenshot`，沿用各服务原有超时、截图回退与错误处理。
5. 截图保存复用 `HostPlatformService.generateScreenshotPath` 与 `copyImageToClipboard`。在设备请求前获取宿主服务和设置快照，页面退出后仍可完成本地写盘，反馈仅在 context 有效时展示。

本需求不新增设备轮询、CLI 命令封装或窗口通信协议。普通投屏沿用 `openStandaloneMirrorWindow`，AirPlay 沿用 `openAirPlayMirrorWindow`，不复制窗口创建和跨 Isolate 同步逻辑。

## 验证

- `test/device_context_action_test.dart`：Android / HarmonyOS、离线、iOS USB / network、AirPlay LIVE 与虚拟设备能力边界。
- `test/device_list_context_menu_test.dart`：实际设备行右键、菜单完整性、截图目标、图片写盘及剪贴板、三平台后端分流、离线/删除拦截、进度与重复操作保护、失败恢复、工具 Route、英文暗色菜单及纯 AirPlay 入口。
- `test/support/device_context_menu_fixture.dart`：隔离设备发现、原生设置广播和剪贴板，图片仅写入临时目录；目标工具使用轻量 Route 测试桩，避免测试时启动终端或投屏进程。
- 关联回归覆盖设备筛选与展示、Dashboard 导航、主窗口 Route、AirPlay 设备合并及 iOS 截图后端。
- 2026-11-06：上述新增用例与关联回归共 8 个测试文件、45 项测试全部通过，其中新增 18 项；11 个修改或新增 Dart 文件定向 `dart analyze` 无诊断，`git diff --check` 通过。
- 全仓 `flutter analyze --no-pub` 无 error，仍报告 38 条任务外既有 warning/info，未混入本次变更。
- 未启动桌面项目；真实设备截图、系统剪贴板和独立投屏窗口仍需运行包验收。
