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
- 应用窗口创建由主窗口的 `AppMirrorWindowCreationGate` 接收子窗口 MethodChannel 请求并串行化 `getAll/create`，避免跨 Isolate 双击时并发创建两个同 App 副屏。创建队列不覆盖随后最长 55 秒的首帧等待；不能使用 Dart `FileLock` 代替，因为同一进程中的多个句柄不会互斥。
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

API 34、35、36 和厂商 ROM 的上述真机验收尚未完成。DRM/`FLAG_SECURE` 画面及部分 App 的副屏行为可能受平台限制，应按实际设备记录，不把 Server 产生日志或 Texture 注册视作画面成功。

## 本次自动验证记录

- 2026-11-06：`flutter test --no-pub` 定向运行 5 个相关测试文件，25 项通过，覆盖默认值、关闭后主屏启动、同一 App 点击合并、窗口并发复用、物理设备与并发音频焦点、错误页主动回退、resize 消息和原有摄像头会话。
- `flutter analyze --no-pub` 无本次新增错误；全仓仍有 38 条已有的 warning/info，命令退出码为 1。提交前的 `git diff --check` 通过。
- 全量 `flutter test --no-pub --reporter compact` 在最后几项局部修正前运行，结果为 1208 项通过、4 项跳过、28 项失败。失败用例涉及真实设备性能探针、品牌资源路径、旧 Dashboard Widget 断言、应用筛选和其他未改模块；应用筛选相关失败已在独立 HEAD 基线复现。局部修正之后重新运行了上述 25 项定向测试；全仓 `dart analyze` 仍为 38 条已有 warning/info。
- 本次没有启动 AnyDeck 或操作手机图库。API 34 真机上的首帧、图库 Task、触控、窗口缩放和关闭回收仍须按上表验收；API 35 设备结果不能替代 API 34 验收。
