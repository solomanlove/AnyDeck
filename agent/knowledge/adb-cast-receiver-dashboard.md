# 投屏接收统一管理页

## 1. 业务目标

- 将设备管理标题栏中的 AirPlay 与 DLNA 图标迁移到左侧一级入口“投屏接收”。
- 用户通过 `/receivers` 页面理解两种协议差异并管理服务，避免把全局接收服务误认为当前设备操作。
- AirPlay 用于 iPhone / iPad 屏幕镜像；DLNA 接收各平台中支持该协议的视频 App 下发的媒体与播放控制，不代表设备屏幕镜像。

## 2. 路由与页面结构

```text
/devices       设备管理
/emulators     模拟器管理
/receivers     投屏接收
```

- `DashboardRouteState.receivers()` 使用全局 Tab index `-3`。
- 进入 `/receivers` 时清空当前设备选择，使左侧稳定展示设备管理、模拟器管理和投屏接收三个一级入口。
- `ReceiverDashboardTab` 使用统一 `DashboardHeaderBar`，内容区按宽度自适应：宽窗口双列、窄窗口单列。
- `ReceiverServiceCard` 统一协议图标、用途说明、状态、启停 Switch、接收端名称和附加动作。
- 服务 Card 下方展示常见视频 App 投放示例；协议标签只作为版本相关参考，并明确受平台、内容版权与会员权益影响。爱奇艺官方说明明确支持 DLNA/AirPlay；小红书当前版本实测支持 DLNA、不支持 AirPlay。

### 兼容示例证据边界

- 哔哩哔哩官方投屏帮助确认移动端投屏与 iOS/iPadOS 本地网络发现，但未提供长期稳定的逐平台协议矩阵：https://www.bilibili.com/blackboard/activity-U_aG4BWWl.html
- 爱奇艺官方投屏助手明确列出支持 DLNA/AirPlay 的设备，同时提示部分内容受版权限制：https://www.iqiyi.com/common/pushvideo.html
- 抖音与腾讯视频的协议标签按当前客户端示例展示，仍需在具体 App 版本、平台和内容上以投屏列表为准。
- 小红书官方公开资料未找到通用协议说明；2026-10-27 用户实测确认当前版本支持 DLNA、不支持 AirPlay，具体平台与版本未记录，后续仍以 App 内投屏列表为准。

## 3. 状态与生命周期

- AirPlay 继续使用 `airplaySessionProvider`，页面不新增第二份状态；开启、停止与活跃投屏窗口恢复沿用现有 Notifier 和窗口路由。
- `AirPlayServerNotifier` 通过 `listenSelf` 保存最后会话，销毁回调不再直接读取 Riverpod `state`，确保页面或测试容器卸载时仍能安全停止底层会话。
- DLNA 继续使用 `DlnaRendererService.instance`；页面注册 `ChangeNotifier` listener，并在 `dispose` 中移除。
- DLNA 页面沿用原播放器 Loading 与置顶双语文案同步，名称仍由 `appSettingsProvider` 持久化并热更新服务。
- 页面通过 `IndexedStack` 保持状态；离开页面不会自动停止服务，用户必须显式关闭 Switch 或退出 App。
- 两种服务当前只在 macOS 启动，其他平台点击启停时显示本地化提示。

## 4. 改动范围

- Route：`lib/app/router/dashboard_route.dart`、`lib/app/router/app_router.dart`
- 左侧导航：`lib/features/overview/dashboard_rail.dart`
- 页面与公共 Card：`lib/features/receivers/`
- Dashboard 装配：`lib/features/dashboard_screen.dart`、`lib/features/overview/dashboard_shell.dart`
- 状态展示：`DlnaRendererService.hasActiveMedia`
- l10n：`lib/app/l10n/tables/app_l10n_ios_tools.dart`
- 删除原顶部入口：`airplay_toolbar_button.dart`、`dlna_toolbar_button.dart`

本次没有新增依赖、ADB 命令、后台进程或跨 Isolate MethodChannel。

## 5. 测试影响与回归方案

### 自动验证

```bash
flutter analyze --no-pub
flutter test --no-pub
```

### 手工验证

1. 左侧依次显示“设备管理 / 模拟器管理 / 投屏接收”，设备管理标题栏不再显示 AirPlay、DLNA 图标。
2. `/receivers` 在宽窗口双列、窄窗口单列显示两个协议 Card，Light / Dark 与中英文状态可读。
3. 开启 AirPlay 后，iPhone 控制中心能发现配置名称；连接后状态与设备数刷新，点击“打开投屏窗口”能恢复窗口。
4. 关闭 AirPlay 时全部广播槽位和活跃会话停止，随后可再次开启。
5. 开启 DLNA 后，Android / HarmonyOS 视频 App 能发现配置名称；投放后状态变为正在接收视频。
6. DLNA 播放期间修改名称不打断当前媒体；关闭 Switch 后发送 SSDP `byebye` 并关闭播放器。
7. 服务运行时切换到其他一级页面，确认服务保持运行；回到投屏接收页后状态不丢失。

## 6. 验证边界

- Widget 与 Route 测试只验证导航、双语 UI 和控件装配，不等同于局域网发现或真机投屏验收。
- 按项目规则不自动启动桌面 App；AirPlay、DLNA 真机链路仍按各自 Knowledge 的验收清单执行。
