# Android 融合投屏

## 用户行为与平台门槛

- Android 14（API 34）及以上首次使用默认开启“融合投屏”。设置在设备的应用页工具栏下方；关闭后只影响之后新开的应用窗口，既有 App 副屏窗口继续运行。同一 App 再次打开时先聚焦既有副屏窗口。
- 关闭后，应用投屏入口先将目标 App 的既有 RootTask 迁至 display 0，再通过 MAIN/LAUNCHER Intent 显式启动，随后打开或聚焦整机投屏窗口。创建普通窗口时不传 `startApp`、`newDisplay`，避免被窗口层误识别为 App 副屏。
- API 33 及以下不启用融合。系统版本或物理身份查不清时使用普通投屏并提示。HarmonyOS 走现有 HDC App 启动和投屏服务；iOS 走现有投屏窗口，不发送 Android display 命令。
- “应用列表操作”“应用详情操作”“整机投屏窗口前台应用操作”“投屏窗口应用快捷操作”统一通过 `AppMirrorLaunchCoordinator` 路由。普通“启动”按钮仍单独控制手机上的 App。

## 数据与多窗口

- `FusionModePreference` 只保存显式选择；缺失值在 API 34+ 解释为开启。键为物理序列号，不把 IP、端口或 mDNS transport 当永久身份。USB 与无线连接若归属同一序列号，会共用选择。
- `deviceFusionModeProvider` 提供 `enabled / disabled / unsupported / unknown`；未知时 UI 不允许修改。应用页切换后使用 `SharedPreferencesAsync` 写入，并对投屏子窗口发送 `fusionModeChanged` 以刷新状态。每次应用投屏启动前回读 SDK 和偏好，避免旧窗口持有过期值。
- 主窗口与子窗口属于不同 Isolate。窗口参数携带 `physicalDeviceKey`；`createAdbManageWindow()` 对同一物理设备和包名复用融合窗口，副屏初始分辨率变化不产生重复窗口。`AndroidMirrorTransportHost` 负责同一窗口内 USB、TCP、TLS 换线；音频焦点按物理设备归并，因为 scrcpy 采集的音频是设备级。
- 两个 App 窗口并发启动时，各窗口按窗口 ID 独立算出相同的唯一音频获胜者；较旧数字窗口先静音，避免双方互相静音或同时播放。关闭后以同一顺序选择剩余窗口。
- 应用窗口创建由主窗口的 `AppMirrorWindowCreationGate` 串行化 `getAll/create`，避免跨 Isolate 双击时并发创建两个同 App 副屏。主窗口在 `runApp` 前注册 `any_deck/app_mirror_window_creation` 单向 `WindowMethodChannel`；子窗口经此通道请求主窗口，主窗口自身直接进入队列。创建队列不覆盖随后最长 55 秒的首帧等待；不能使用 Dart `FileLock` 代替，因为同一进程中的多个句柄不会互斥。
- `AppMirrorLaunchCoordinator` 在单个 Isolate 中按设备、包名和目标模式合并重复点击，共享启动与首帧等待；跨 Isolate 的窗口创建仍由主窗口队列保证唯一。

## 副屏、尺寸与回收

- `EmbeddedScrcpyService` 仍使用内置 scrcpy 4.0 Server、独立 `scid`/ADB forward、Rust VideoToolbox Texture。融合会话传 `new_display`、`flex_display=true`、`vd_destroy_content=false`、`vd_system_decorations=false`、`display_ime_policy=local`。首次虚拟屏尺寸至少保留在 `max_size` 限制内，实际硬件编码器仍可能进一步降尺寸。
- 从 Server 日志取得 display ID 后，先迁移已有 RootTask 或执行 `am start --display <id>`，再等 Rust 首个 CVPixelBuffer。`mirrorSessionStatus` 同时要求视频尺寸可用、display ID 已取得且 Controller 无错误。未在规定时间获得首帧时向入口返回错误，子窗口展示重试和用户主动选择的“改用普通投屏”。
- scrcpy 4.0 的 `TYPE_RESIZE_DISPLAY=21` 消息为一个类型字节加两个 big endian `uint16` 宽高。融合窗口在拖动结束后按 Viewer viewport 发送尺寸；设备更新帧尺寸后 Viewer 继续按真实视频帧映射触控。此链路需要 Android 真机检查 App 是否重排，以及编码器降尺寸后的画面与触控。
- 已用 `droidasc` 核对仓库内 `assets/scrcpy/scrcpy-server.jar` 的 DEX：`Options` 接收 `flex_display` 和 `display_ime_policy=local`；`ControlMessageReader` 在类型 21 后读取两个 `readUnsignedShort()`；`NewDisplayCapture.requestResize()` 仅在 flex 模式处理尺寸请求。
- 启动失败时注销 Texture、停止 Rust handle、终止 scrcpy 进程并移除 ADB forward；Activity 逃逸守护 Timer 在失败、停止或关闭窗口时取消。`vd_destroy_content=false` 仅要求 Android 尽量迁回 Task，不保证所有厂商 ROM 都保留页面状态。

## 验证与验收

本次自动测试覆盖 API 34 默认值和 USB/无线偏好、API 33 门槛、主屏 display 0 启动、窗口复用、开关 UI、HarmonyOS 路由、音频焦点及 resize 消息。静态分析与测试结果以本次提交记录为准；自动测试不等于真实副屏画面、触控或设备端 Task 的验收。

| 真机用例 | 需要观察的结果 |
| --- | --- |
| API 34 首次连接，打开图库 | Switch 默认开；`dumpsys display` 有新 display ID；图库 Task 在该 display `RESUMED`；Mac 窗口有可交互首帧 |
| 关闭后重连、重启、USB 与无线切换 | Switch 保持关闭；图库在 display 0；整机投屏显示同一画面 |
| 两个 App 副屏与手机主屏并用 | 三处画面互不串屏，触控与键盘焦点正确；同 App 重开只聚焦旧窗口；音频只播放一次 |
| 缩放、旋转、跳转和输入法 | App 对新 viewport 重排，触控坐标准确；IME 在副屏；跨 App 跳转的 Task 去向可解释 |
| 关闭、断线、启动失败 | display、server、forward、Rust handle 与 Texture 回收；失败时只由用户主动选择普通投屏 |

API 34、35 的上述真机验收尚未完成；API 36 目前仅完成荣耀 Magic V6 图库的首帧、Task、触控和缩放验收。DRM/`FLAG_SECURE` 画面及部分 App 的副屏行为可能受平台限制，应按实际设备记录，不把 Server 产生日志或 Texture 注册视作画面成功。

## 本次自动验证记录

- 2026-11-06：`flutter test --no-pub` 定向运行 5 个相关测试文件，25 项通过，覆盖默认值、关闭后主屏启动、同一 App 点击合并、窗口并发复用、物理设备与并发音频焦点、错误页主动回退、resize 消息和原有摄像头会话。
- `flutter analyze --no-pub` 无本次新增错误；全仓仍有 38 条已有的 warning/info，命令退出码为 1。提交前的 `git diff --check` 通过。
- 全量 `flutter test --no-pub --reporter compact` 在最后几项局部修正前运行，结果为 1208 项通过、4 项跳过、28 项失败。失败用例涉及真实设备性能探针、品牌资源路径、旧 Dashboard Widget 断言、应用筛选和其他未改模块；应用筛选相关失败已在独立 HEAD 基线复现。局部修正之后重新运行了上述 25 项定向测试；全仓 `dart analyze` 仍为 38 条已有 warning/info。
- 首版提交时没有由开发过程启动 AnyDeck 或操作手机图库。API 34 真机上的首帧、图库 Task、触控、窗口缩放和关闭回收仍须按上表验收；API 35 设备结果不能替代 API 34 验收。

## 运行反馈与修复（2026-11-06）

- 用户在 Mi MIX 3 的应用列表及已打开的投屏窗口点击应用投屏，均出现 `CHANNEL_UNREGISTERED`：`mixin.one/window_controller/0` 不可访问。失败发生在子窗口请求主窗口创建新窗口时，尚未进入副屏启动链路。
- `desktop_multi_window 0.3.1` 在 macOS、Windows、Linux 均给主窗口分配动态 ID；先前代码将主窗口 ID 写死为 `0`，配套单元测试也模拟了这个错误 ID。现改用插件支持的 `ChannelMode.unidirectional`，由主窗口完成注册后再显示 UI，子窗口调用固定业务通道，不依赖窗口 ID。仓库中写死主窗口 ID 的多窗口规则与技能文档已同步纠正。
- 回归测试验证子窗口使用业务通道、主窗口以单向模式注册并本地串行创建。Dart 测试与静态检查只能验证调用契约；需要完全退出并重新启动当前运行的 AnyDeck 后，才能验证主窗口注册以及真实副屏首帧，Hot Reload 不会重新执行主窗口初始化。
- 修复后定向运行 5 个相关测试文件，26 项通过；全仓 `dart analyze` 仍有 38 条既有 warning/info，无本次新增诊断。尚未对重启后的真实窗口创建、App Task 和首帧完成运行验收。
- 提交前补充复核 5 个测试文件，38 项通过；对 `app_mirror_window_creation_gate.dart`、`main.dart` 和 `apk_window_open_test.dart` 分别执行 `dart analyze`，均无诊断。

## 图库缩放对齐与真机验收（2026-11-06）

- 参考软件 AndroMeld 在荣耀 Magic V6 的同一图库 Task 上保持独立虚拟屏：窄窗口约 `1384×1600 / 197 dpi`，宽窗口约 `1600×924 / 114 dpi`。两者逻辑高度都约为 1300 dp；图库从三列切为五列，过程中可见模糊旧画面和居中网格图标。设备侧 Helper 调用 `VirtualDisplay.resize(width, height, dpi)`；仓库内 scrcpy 4.0 Server 的 resize 控制报文仅携带宽高，故 AnyDeck 需另外调整副屏 DPI。
- `FusionDisplayGeometry` 以 Viewer viewport 为输入，最长边限制为 1600 像素，按约 1300 dp 逻辑高度计算 DPI。创建副屏时就传同一规则的初始尺寸；窗口改变后发送 scrcpy 控制报文类型 21。`FusionResizeTransition` 在等待新视频帧时模糊旧画面、显示网格图标，并阻止误触；新帧和 DPI 到位后撤掉过渡层，最长等待 5 秒。
- 连续 resize 使用 `FusionDisplayUpdateQueue` 串行处理尺寸和 DPI。scrcpy 的 `sendControl` 只确认写入 socket，不代表 Android 已完成 `VirtualDisplay.resize`；先前立即调用 `wm density` 会被稍后的 resize 覆盖。现在轮询 `wm size -d <displayId>`，确认目标物理尺寸后才设置 `wm density <dpi> -d <displayId>`；会话停止时执行 `wm density reset -d <displayId>`。同一会话中的 ADB 命令有超时和设备身份检查。
- 没有现存 Task 时，先以 `cmd package resolve-activity` 查找 `MAIN/LAUNCHER` Component，再显式 `am start -n`。找不到入口时在创建融合窗口前返回错误；已有 Task 可直接迁移，无需 LAUNCHER Activity。该处理覆盖用户反馈的 `unable to resolve Intent` 和无启动 Activity 的空白投屏窗口，但不使原本不能独立启动的系统组件变为可启动 App。
- 真机窗口：荣耀 Magic V6，Android 16，USB，`com.hihonor.photos`。AnyDeck 首帧真实可见，图库 Task `#704` 在虚拟屏 `displayId=123` 的 `RESUMED` 状态；首次窄窗口 `714×1600 / 197 dpi` 为三列，宽窗口 `1600×1106 / 136 dpi` 为五列，缩回 `1410×1600 / 197 dpi` 为三列。宽窄两向均观察到模糊与居中网格过渡；点击缩略图进入照片并通过返回键回到图库。调节的是窗口宽高比，实际副屏像素值随窗口尺寸而变。
- 首次复测发现从宽缩窄后副屏为 `1410×1600`，DPI 却仍为 `136`；排查确认 `wm density 197 -d 122` 可手动生效。加入等待物理尺寸的时序修复后，同样的宽窄往返在 `displayId=123` 实测恢复到 `197 dpi`。21:00–21:22 CST 的 `AndroidRuntime:E` 定向日志中未检出图库或 shell 的 `FATAL EXCEPTION`；图库进程 PID 6878 仍在运行。
- 四个定向测试文件共 17 项通过；改动 Dart 文件 `dart analyze` 无诊断，`flutter build macos --debug --no-pub` 通过，`git diff --check` 通过。此次真机验收覆盖上述荣耀图库路径；Android 14/15、其他 ROM、受保护画面和像素级动画一致性仍须分别验证。图库私有缩略图未保存到仓库。
