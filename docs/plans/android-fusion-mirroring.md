# AnyDeck Android 融合投屏实施方案（调研版）

日期：2026-11-06

## 1. 目标与产品规则

本方案将“融合投屏”定义为：手机上的一个 Android App 运行在独立 `VirtualDisplay`，桌面端为其显示、控制一个独立窗口；手机物理屏可继续使用其他 App。按需求将 **Android 14 及以上（API 34+）**作为默认启用范围。连接手机本身不启动投屏，只有用户打开 App 时才建立会话。

| 设备与状态 | 默认开关 | 点击“应用投屏”后的行为 |
| --- | --- | --- |
| Android API 34+，无用户记录 | 开 | 新建或复用该 App 的融合窗口 |
| Android API 34+，用户已关闭 | 关 | 在手机主屏启动 App，并新建或复用普通整机投屏窗口 |
| Android API 34+，用户再次开启 | 开 | 后续新开的 App 使用融合窗口 |
| Android API 33 及以下、HarmonyOS、iOS | 不提供融合开关 | 使用各平台现有投屏或启动能力，不创建 Android 融合窗口 |
| Android API 未查明或设备离线 | 显示检测中/不可操作 | 在线时单次回读 `ro.build.version.sdk`；仍未知则提示并使用普通投屏 |

开关放在当前设备“应用”页搜索工具栏下方的独立设置行，避免挤压现有搜索、视图切换和安装按钮；名称为“融合投屏”，说明文字明确“只影响之后新开的应用窗口”。建议按**物理设备**持久化：一台 Android 手机关闭融合投屏，不改变另一台手机的默认值；同一手机 USB、TCP/IP 和无线调试连接共用设置。已有融合窗口在关闭开关后继续运行，用户关闭该窗口后再打开 App 才按普通投屏处理。若该 App 仍占用融合窗口，再次点击时聚焦现有窗口并说明当前模式，避免同时迁移同一个 Task。

“关闭”不等于禁用手机投屏，也不关闭现有会话。普通模式必须先在 display 0 启动目标 App，再打开或聚焦整机投屏窗口。现有 `MirrorWindowController` 用 `startApp != null` 识别应用副屏，因此不能仅将 `newDisplay` 置空并保留 `startApp`：那会把普通窗口误判为应用窗口，却不会执行 App 启动。

## 2. 调研依据与当前基础

- 2026-11-06 的 AndroMeld 实机与现版 APK 分析显示独立 `VirtualDisplay`、按 display ID 启动 Activity、编码视频帧并在桌面独立窗口渲染；图库在 API 35 真机的副屏处于 `RESUMED`。图库桌面画面的可视验收仍未完成。
- AnyDeck 的 `dashboard_apps_actions.dart`、`dashboard_app_functions_view.dart`、`mirror_window_controller.dart` 和 `mirror_app_quick_actions_controller.dart` 共四处应用投屏入口，当前均传 `newDisplay` 与 `startApp`，缺少统一模式判断。
- `EmbeddedScrcpyService.start()` 已通过 shell 身份运行内置 scrcpy 4.0 Server，使用 `new_display`、独立 `scid`、ADB forward 和 Rust/VideoToolbox Texture。`app_virtual_display_launcher.dart` 在取得 display ID 后迁移已有 Task 或执行 `am start --display`，并等待首帧。`vd_destroy_content=false` 用于副屏释放后尽量把任务送回主屏。
- `deviceSdkVersionProvider(deviceId)` 已从设备注册表提供 `int? sdkVersion`，元数据探测读取 `ro.build.version.sdk`；`RegisteredDevice.serial` 与 `connections` 可用于同一手机跨 USB/无线连接的身份归一。
- `createAdbManageWindow()` 当前根据 `type + deviceId + newDisplay + startApp` 复用窗口。副屏分辨率改变时，同一 App 可能被误判为新窗口；融合模式应改用物理设备标识、包名与模式作为会话键。
- 现有 `MirrorAudioFocusCoordinator` 按设备协调播放，但 scrcpy 的音频采集范围是整台设备。它不能天然分出“仅当前融合 App”的声音；跨 USB/无线 transport 也应按物理设备归并音频焦点。
- 仓库记录了 2026-09-27 的 API 35 单 App 真机画面、触控和独立 socket 验证；该记录不替代本方案实施后的 API 34 真机验收。

上游 [scrcpy 4.0 虚拟显示文档](https://github.com/Genymobile/scrcpy/blob/v4.0/doc/virtual-display.md)支持 `new_display`、在副屏启动 App、关闭副屏时迁回内容和本地 IME 策略。AndroMeld [帮助中心](https://andromeld.catchingnow.com/zh-Hans/help.html)将其产品的融合模式限定在 Android 14+；这属于本方案采纳的产品门槛，不能推论 scrcpy 在所有较低版本系统上都不支持虚拟显示。

## 3. 架构方案

### 3.1 数据层

新增设备级 `FusionModePreference`，值只记录用户的显式选择。缺失值在 API 34+ 解释为 `true`，API 33 及以下解释为不可用；不在首次连接时批量写入 `true`。持久化键使用稳定物理序列号，若当前只有网络 ID，先通过现有设备身份解析取得 serial，再保存；身份未确认时不以临时 IP:Port 写入永久设置。数据模型至少区分 `loading / supportedEnabled / supportedDisabled / unsupported`，避免把 SDK 未知误作用户关闭。

主窗口负责写入设备偏好；子窗口需要打开应用时读取同一有效策略，变更通过现有窗口消息广播更新。读取和写入按设备串行，防止两个 Isolate 用旧缓存覆盖最新选择。SDK 使用注册表缓存显示 UI，首次实际启动前对缺失或过期的版本做一次有界回读，不增加常驻 ADB 轮询。

### 3.2 逻辑层

新增单一 `AppMirrorLaunchCoordinator`，所有四处入口都调用它，输入为设备、包名与入口来源，输出为融合窗口、普通投屏窗口或明确错误。它负责：

1. 校验在线状态、Android 平台、SDK 与设备级开关；为同一设备同一 App 合并并发点击。
2. 融合模式下复用现有 App 窗口；否则创建 `newDisplay + startApp` 子窗口，等待 display ID、目标 Activity `RESUMED` 和可显示首帧。已有 Task 迁移会使手机上的该 App 转到副屏，界面应把它描述为“接续使用”，不承诺同一 App 双开。
3. 普通模式下显式把目标 App 启动或迁移到 display 0（必要时复用现有 App 启动服务），随后复用或打开 `startApp == null` 的整机投屏窗口。窗口标题仍是设备名，避免把整机画面标成单 App 隔离窗口。
4. 创建副屏失败时清理本次 server、socket、forward 与 Texture，显示具体失败原因和“改用普通投屏”操作；未经用户选择不悄悄改在手机物理屏启动敏感 App。
5. 关窗、拔线、切换 USB/无线通道和重连时，按会话 ID 清理或恢复。开关变动只影响新会话，不强停正在使用的 App。

继续使用 scrcpy shell 进程创建副屏和注入输入，不复制 AndroMeld 的隐藏 API 或 Android 16 `VirtualDeviceManager` 分支。Android 官方的 [Companion app streaming](https://source.android.com/docs/core/permissions/app-streaming)要求特定 role，完整 role 仅面向预装特权 App；`ActivityOptions.setLaunchDisplayId()` 本身也受目标 display 的访问控制限制。

### 3.3 UI 层

- “应用”页搜索工具栏下方在选中 Android 设备时显示融合投屏 `Switch`；API 34+ 默认为开，低版本显示不可用原因。切换成功后立即更新当前设备 UI，并在重新连接、切换设备、重启 AnyDeck 后保持结果。
- 现有“应用投屏”按钮根据有效模式展示“融合投屏”或“普通投屏” tooltip；“启动”按钮继续只负责手机启动。应用详情和投屏窗口内的快捷入口使用同一 coordinator，不另写一套判断。
- 加载、失败、回退提示、设备不支持提示均使用 zh/en l10n；新控件沿用现有 `CupertinoSwitch` 与 Theme 色。开关旁的说明不展示 SDK 实现细节。
- 若 App 已在融合窗口运行，开关关闭后该窗口保持可用；对同一 App 的再次点击聚焦窗口并提示关闭后可按普通方式打开。不同 App 的新操作立即按关后的模式执行。

## 4. 分期实现与改动范围

| 阶段 | 主要工作 | 验收门槛 |
| --- | --- | --- |
| A：默认值与开关 | 设备级偏好、API 34 门槛、应用页 Switch、统一四处入口、普通模式流程、l10n | API 34 首次连接默认开；关闭、重连、重启和 USB/无线切换后仍关；API 33 不误开 |
| B：融合会话稳定性 | 同 App 窗口复用键、并发防抖、首帧和 task 校验、失败清理、断线恢复、音频焦点按物理设备归并 | 两个 App 与手机物理屏可同时使用；无串屏、串输入、重复音频或残留副屏 |
| C：完整窗口体验 | 评估 scrcpy 4.0 `flex_display` 的窗口尺寸回传、local IME、跨 App 跳转与受保护内容提示 | 拖动窗口后 App 按副屏新尺寸重排；输入法、跳转、截图录屏有明确结果和边界 |

预计 A+B 为 4–7 人日，C 另需 3–6 人日，另计 API 34/35/36 与厂商 ROM 真机回归。估计以一名熟悉当前 Flutter、Rust、scrcpy 链路的开发者为前提；C 的工作量取决于内置 Server 对动态 resize 的实际兼容性。

主要文件范围：`lib/features/apps/` 的应用页与详情入口；`lib/app/window/mirror/` 的窗口内入口、会话复用和音频焦点；`lib/app/settings/` 或独立设备偏好文件；`lib/core/scrcpy/` 的副屏启动与资源释放；`lib/app/l10n/tables/`；对应单元和 Widget 测试。完成开发后按仓库规则更新 `agent/knowledge/` 与索引。

## 5. 验收与风险

| 用例 | 必须看到的结果 |
| --- | --- |
| API 34 新设备、用户从未选择 | Switch 为开；点击图库后新增副屏，图库 `RESUMED` 在非 0 display，Mac 窗口出现可交互首帧 |
| API 34 关闭再重连、重启、USB↔无线切换 | Switch 持续为关；点击图库在 display 0 运行，整机投屏窗口显示相同画面 |
| API 35/36 与 API 33 | 35/36 遵循同一默认值和关闭逻辑；33 无融合入口或标明不可用，普通投屏可用 |
| 两个不同 App 融合窗口与手机主屏 | 各自 display ID、socket、画面、鼠标键盘焦点正确；同 App 再点聚焦已有窗口 |
| App 已运行、跨 App 跳转、屏幕旋转、缩放窗口 | Task 去向可解释；画面尺寸与触控坐标一致，失败时提示而不显示别的 display 内容 |
| 关闭窗口、拔线、失败重试 | scrcpy 进程、forward、Rust handle、Texture 和 VirtualDisplay 回收；App 状态按 `vd_destroy_content=false` 尽量回到主屏 |

验证分层：策略与持久化用单元测试；开关、l10n 和多设备切换用 Widget 测试；窗口复用、普通模式和失败清理用集成测试；最终在 **API 34 真机**核对 `dumpsys display/activity`、Mac 首帧、输入及关闭清理。现有 Mi MIX 3 为 API 35，不能代替 API 34 验收。受 DRM/`FLAG_SECURE` 保护的画面和部分厂商 ROM 的副屏行为应记录为兼容性结果，不以日志收到帧代替可视验收。

本文件是方案。实施前先确定 A+B 的交付范围；C 可按完整融合体验另排期。
