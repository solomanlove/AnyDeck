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
- 服务 Card 区与下方投放示例之间保留 16 px 垂直间距；宽窗口双列和窄窗口单列均一致。
- 服务内容区宽度达到 860 px 时，双列使用 `IntrinsicHeight` 配合 `Row` 的 `CrossAxisAlignment.stretch`，按较高卡片动态等高，统一底边。
- 公共 `ReceiverServiceCard` 将上部协议/状态信息和下部名称区分组，使用 `MainAxisAlignment.spaceBetween` 吸收额外高度，保证名称输入框对齐；两区之间最少保留 20 px 间距，支持说明自然换行。
- 内容区小于 860 px 时改为单列，不施加等高约束，每张卡片按内容自然增高；不设置固定高度、不截断说明。额外 intrinsic 测量仅用于双列的两张服务卡片。

### 兼容示例证据边界

- 哔哩哔哩官方投屏帮助确认移动端投屏与 iOS/iPadOS 本地网络发现，但未提供长期稳定的逐平台协议矩阵：https://www.bilibili.com/blackboard/activity-U_aG4BWWl.html
- 爱奇艺官方投屏助手明确列出支持 DLNA/AirPlay 的设备，同时提示部分内容受版权限制：https://www.iqiyi.com/common/pushvideo.html
- 抖音与腾讯视频的协议标签按当前客户端示例展示，仍需在具体 App 版本、平台和内容上以投屏列表为准。
- 2026-11-08 按用户提供的兼容信息补充 HarmonyOS 版央视频、芒果 TV、腾讯视频支持 DLNA：新增前两者的 DLNA 示例卡片，腾讯视频保留原有协议标签并明确 HarmonyOS 的 DLNA 支持；其他平台与协议仍以当前 App 版本为准。该信息由用户提供，本次未独立进行真机投放验证。文案同步维护 zh/en，复用原有卡片布局与 Theme。
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

`receiver_dashboard_tab_test.dart` 覆盖以下布局回归：

- 中英文、Light/Dark、1.0/1.3 字体倍率，以及包含双列/单列临界值的五种窗口宽度。
- 双列卡片顶边、底边与名称输入框顶底边对齐。
- 同宽卡片从双列切换为单列后，单列自然高度最大值与双列高度一致；单列长说明卡片比短说明卡片更高。
- 宽窄布局中服务 Card 与投放示例实际垂直间距为 16 px；单列卡片之间也为 16 px。
- 原有 AirPlay 镜像/视频窗口入口按状态显示的回归。

本次仅调整页面与公共 Card 布局，复用现有 Theme、l10n 和状态管理，不改变投屏链路或启停/名称持久化逻辑。

```bash
flutter analyze --no-pub
flutter test --no-pub
```

### 2026-11-07 布局验证记录

- `flutter test --no-pub test/receiver_dashboard_tab_test.dart`：6 项测试通过，布局测试包含 40 组宽度/语言/主题/字体倍率组合。
- `dart analyze lib/features/receivers test/receiver_dashboard_tab_test.dart`：无问题。
- `git diff --check`：通过。
- `flutter analyze --no-pub` 在 language-server 启动后持续无输出，已停止该次检查，改用 `dart analyze` 完成全仓扫描：发现其他文件中的 6 项 warning 和 32 项 info，本次未修改这些文件；不将全仓检查表述为通过。
- 未启动桌面 App，真实窗口视觉验收仍需手工确认。

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

### 2026-11-08 鸿蒙 App 支持说明回归

- 变更范围：`receiver_app_support_guide.dart`、`app_l10n_ios_tools.dart` 与页面 Widget 测试。
- 页面测试检查三款 App 的支持说明，并在已有 40 组宽度/语言/主题/字体倍率组合中检查新增文案和布局异常。
- 仅补充兼容示例，不新增 Provider、后台进程、依赖或跨窗口通信；投屏接收链路沿用现有实现。
- 验证结果：`flutter test --no-pub test/receiver_dashboard_tab_test.dart` 6 项通过；`flutter analyze --no-pub` 定向检查上述三个 Dart 文件无问题；本次文件 `git diff --check` 通过。未启动桌面 App。
