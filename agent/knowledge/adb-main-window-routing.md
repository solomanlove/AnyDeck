# Knowledge: adb-main-window-routing（主窗口层级路由）

## 目标

主窗口使用 `GoRouter` 表达设备管理、模拟器、设置、设备工具和应用详情层级，URL 是导航位置的 source of truth；Riverpod 继续管理设备数据、ADB 会话、应用缓存和工具运行状态。

## Route hierarchy

```text
/devices
/emulators
/receivers
/system-versions
/settings
/wan-android
/mcp
/devices/:deviceId/:tool
/devices/:deviceId/apps/:packageName
```

设备工具使用稳定 slug：`overview`、`control`、`apps`、`files`、`logs`、`terminal`、`processes`、`webpages`、`capture`、`performance`、`network`、`messages`。禁止把既有 Tab 数字直接写入 URL。

## 实现边界

1. `lib/app/router/dashboard_route.dart` 集中维护 Route name、URI 解析和 slug/index 映射。
2. `ShellRoute` 始终复用一份 `DashboardScreen`，其 child 仅承载 Navigator 历史；设备工具的懒加载 `IndexedStack`、应用筛选和后台会话不会因为 URL 变化整体重建。
3. `dashboard_route_sync.dart` 负责把 URI 参数同步到迁移期仍在使用的 `selectedDeviceProvider`、`selectedToolTabProvider` 和 `selectedAppPackageProvider`。业务点击只能先更新 Route，禁止新增反向拼接路径的状态分支。
4. Splash 是 `MaterialApp.router` 外层的 StartupGate。Router 首地址为 `/devices`，动画只覆盖并预热当前路由页面，动画结束不进入返回栈。
5. `/emulators` 展示主窗口内嵌完整模拟器管理页，不再提供独立管理窗口。AVD、DevEco、iOS Simulator 的运行画面仍使用各自原有窗口。
6. `/receivers`、`/settings`、`/wan-android`、`/mcp` 是全局页面，不要求 `deviceId`；进入 `/receivers` 会与设备/模拟器管理页一样清空当前设备选择。设置修改仍经 `appSettingsProvider` 和既有 MethodChannel 广播同步子窗口。

## 导航行为

- 单击设备行进入 `/devices/:deviceId/overview`，批量选择由 Checkbox 独立承担。
- 设备工具栏切换使用 `goNamed(deviceTool)`，避免数字 Tab 进入路径。
- 应用详情使用 `push` 保留应用列表返回位置；详情返回优先 `pop`，无历史时回到同设备 `/apps`。
- 通知点击和 Finder APK 安装后的“查看已安装应用”也必须更新 Route，不能只写 Provider。
- 不支持的平台工具继续回退到对应设备的 `overview` Route。

## 验证与回归

- `test/dashboard_route_test.dart` 覆盖顶层页面（含投屏接收）、含冒号设备 ID、应用包名及工具 slug/index 映射。
- 手工回归需覆盖 Splash → 设备列表、设备 → 各工具、应用详情返回、模拟器主页面/独立窗口、设置快捷键、通知点击和 Finder APK 安装跳转。
- 静态检查和 Widget 测试不等同于桌面窗口、真实设备或系统通知验收；按仓库规则不自动启动应用。

## 2026-10-28 导航收口

- `/emulators` 是唯一模拟器管理入口，已移除独立管理窗口及原生菜单；模拟器运行画面和设备投屏仍可独立展示。
- `/system-versions`（迁移期 Tab `-5`）为全局页面，进入时清空设备选择。
- 控制台是 Shell 底部面板，不占用 Route；独立控制台仍可从面板打开。详见 `adb-main-window-navigation.md`。
