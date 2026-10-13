# 投屏独立窗口行为机制

## 背景

投屏独立窗口由 `MirrorWindowApp` 渲染窗口外壳，由 `MirrorWindowController` 维护 scrcpy 会话、窗口状态和比例适配。窗口内的 `Texture` 必须保持设备画面比例，不能为了铺满窗口直接拉伸，否则会破坏鼠标与触控坐标映射。

## 比例适配

- 启动投屏后，控制器会等待 scrcpy video size 可用，再调用 `MirrorWindowFrameAdapter.fitWindowToAspectRatio()` 修正外层窗口尺寸。
- Texture 注册仅表示视频通道已建立；独立窗口继续展示 loading，直到 Rust `getVideoSize()` 从首个解码 `CVPixelBuffer` 读到非零宽高。15 秒仍无首帧则显示启动超时，避免先撤掉 loading 后短暂露出黑色 Texture。
- macOS 上视频尺寸跨横竖屏时，先让 scrcpy 解码后的 Android 原生旋转过渡帧在稳定的窗口内显示 350ms，再用原生 `NSAnimationContext` 在 220ms 内将窗口 frame 插值到目标宽高。无需对 Texture 再做一次 90° 旋转，否则会把手机已旋转的画面重复旋转。没有独立的正方形过渡帧；目标 frame 仍以旧窗口中心计算。标题栏和工具栏高度始终另计，视频 Texture 按真实帧比例渲染，触控坐标不随窗口动画拉伸。
- 同方向的尺寸微调仍直接贴合。全屏、原生最大化及其他平台不执行 macOS 方向切换动画；动画过程中若继续收到新帧尺寸，控制器在当前动画结束后按最新比例贴合。
- Android 主屏横竖屏切换必须复用现有 socket、decoder 和 Flutter Texture，禁止因 `dumpsys display` 与视频帧方向短暂不一致而重启 scrcpy session；Viewer 以 `getVideoSize()` 返回的最新解码帧尺寸更新画面比例与触控坐标。
- macOS 原生硬解由纯 Rust (`rust/device_bridge/`) 调用 Apple VideoToolbox 实现显存直通；解码帧尺寸变化时由 Rust 原生输出对应尺寸的 `CVPixelBuffer`，并通过 `RustTexturePlugin.swift` 通知 Flutter Texture 原地更新，彻底剥离 FFmpeg 与 C++。
- scrcpy 4.0 在旋转后会在原 video socket 写入 12-byte session metadata：首个 `u32` 最高位为 session flag，随后是新 `width` 和 `height`。Rust client 必须先识别该 header 并跳过 payload 读取；如果按普通的 `PTS + packet size` 解析，会把新高度误认为 packet size、读乱字节边界并以超大 frame 错误退出。
- 独立窗口不再额外运行 250ms 方向检测与 `dumpsys display` 轮询；`EmbeddedScrcpyViewer` 每 100ms 读取一次 native Texture 尺寸以快速更新比例。只有首帧尚未到达时才每秒读取一次 `displayFrame` 作为占位比例，避免投屏期间持续执行 ADB command。
- video size 变化时以 `textureId + width×height` 作为 `EmbeddedScrcpyTextureSurface` 的 Key，只重建 Flutter Texture widget/layer 以强制重新 layout；native `textureId`、decoder 和 socket 保持不变，避免 macOS external Texture 在第二次方向切换时沿用上一方向的布局缓存。
- 启动、双击黑边或用户缩放收敛时，控制器会先解除 `windowManager.setAspectRatio(0)`，再做一次窗口贴合，最后用 `windowWidth / (windowWidth / contentAspect + mirrorWindowTopChromeHeight)` 调用 `windowManager.setAspectRatio(...)` 锁定后续拖拽缩放；`mirrorWindowTopChromeHeight` 是自定义标题栏和顶部工具栏的固定高度，不能从当前 `windowHeight - viewerHeight` 动态反推，否则会被已有黑边和原生 frame/content 差异污染。
- 用户手动拖动缩放窗口时，由原生窗口管理器维护比例，不在 Dart 层高频调用 `setWindowFrame` / `setBounds`，避免持续刷 `Resize timed out`。
- 用户拖动缩放结束后会延迟做一次收敛贴合，用于抵消标题栏和工具栏固定高度造成的极端尺寸黑边。
- 投屏窗口设置最小窗口尺寸，避免缩得过小时标题栏右侧按钮和设备标题互相挤压。
- 全屏状态会解除比例锁，退出全屏后重新按当前画面贴合并锁定比例。
- 原生窗口最大化或 macOS 绿色系统全屏不会进入应用沉浸全屏；只有投屏窗口右侧 fullscreen icon 会隐藏自定义标题栏和工具栏。
- 全屏状态不强制修正比例，全屏黑边属于容器大于设备画面时的正常表现。

## 应用投屏模式

- `startApp != null` 表示当前窗口是单 App 投屏窗口。
- 每个屏幕投屏会话必须生成独立的非零 `scid`，并转发到匹配的 `scrcpy_<8位十六进制>` abstract socket；禁止继续写死 `scid=0`，否则整机投屏与单 App 投屏会争用同一 socket。
- scrcpy 创建空虚拟副屏后可能不会立即产生视频帧。`EmbeddedScrcpyService` 必须先从 server 日志取得 display ID，通过 `am start ... --display <id>` 把目标 App 启动到副屏，再等待 Rust/VideoToolbox 首个可渲染帧；不能在首帧就绪后才启动 App。
- App 启动使用 package MAIN/LAUNCHER Intent，不直接传 `resolve-activity` 返回的组件名；Activity alias 可能含 `$`（例如 YouTube 的 `Shell$HomeActivity`），会被设备端 `adb shell` 展开并导致错误组件。
- scrcpy 4.0 的虚拟屏参数名是 `vd_destroy_content=true`，不是 `vd_destroy_content_on_removal`；后者会被 server 作为未知参数忽略。
- scrcpy audio playback capture 是设备级而非 App/virtual display 级。单 App 投屏固定 `audio=false`，由同设备整机投屏承担音频，避免两个窗口同时播放同一设备音频；标题栏也不显示音频转发标识。
- 单 App 投屏窗口不再在标题栏展示“打开应用投屏”的 app icon，避免在应用投屏内继续递归打开应用投屏。
- 顶部工具栏在非全屏状态下仍展示，保持返回、Home、截图、录屏、设备设置等快捷控制可用。
- 长按返回键强停前台应用时，停止命令仍以包名执行；如果 `MirrorWindowController.currentForegroundPackage` 已经拿到本地 icon 且 label 非空，则轻提示优先展示应用名，避免把包名直接暴露给用户。
- 长按返回键强停成功后必须清空 `currentForegroundPackage` 并通知 UI，标题栏 app icon 需要立即隐藏；强停失败时保留现有前台应用状态，便于用户重试或重新识别。

## 投屏窗口提示

- 投屏独立窗口内的轻提示统一使用 `lib/app/widget/app_toast.dart` 中的 `AppToast.show(...)`。
- `AppToast` 通过 `OverlayEntry` 渲染在当前窗口居中位置，不依赖 `ScaffoldMessenger`，适合投屏子窗口、设置弹窗返回后的提示、拖拽安装/上传结果、截图/录屏结果、剪贴板发送失败、返回键和音量键长按提示。
- 新增投屏提示时优先按语义选择 `AppToastType.success`、`error`、`warning`、`info`，只有需要兼容旧调用时才使用 `isError` 参数。

## 沉浸式窗口控件与 Session 状态

- 全局“始终显示投屏控制栏”设置默认关闭，继续使用自动隐藏；开启后 Android、HarmonyOS、iOS USB 与 AirPlay 投屏均持续显示标题栏、系统窗口按钮和右侧工具栏。设置通过多窗口通道实时同步到已打开的投屏子窗口。
- 标题栏和右侧竖排工具栏位于视频 Texture 外部。显隐前后外层窗口与视频区域尺寸保持不变；显示时两块区域绘制 Theme surface 背景，隐藏时背景与内容一起透明，不额外保留隐藏标识条。窗口不再保留底部栏及其占位。
- 投屏子窗口隐藏 macOS 原生关闭、最小化和最大化按钮；三个控制区与窗口 Scaffold 均使用透明背景，并将原生窗口背景设为 clear，使固定槽位可透出后方桌面。透明区域仍属于当前窗口，不提供鼠标点击穿透。
- macOS 三个系统窗口按钮跟随标题栏显隐：标题栏出现时恢复按钮，自动隐藏时同时隐藏。右侧工具栏背景由固定槽位完整绘制，必须覆盖按钮列表上方和下方的空白区域。
- macOS 标题栏左侧必须为原生 Traffic Light 按钮预留空间，设备名位于系统按钮右侧，窗口功能按钮保持右对齐，禁止相互覆盖。
- 当前窗口显示 Dialog 等 ModalRoute 时，标题栏、系统窗口按钮和右侧工具栏必须保持显示，并暂停自动隐藏；弹框关闭后再恢复空闲隐藏计时。
- 投屏处于 loading、启动失败或断开等非画面状态时，窗口恢复 Theme surface 实体背景并保持控制区显示；仅在可见投屏画面正常输出后启用外围透明与自动隐藏。
- loading 阶段仍需构建并显示右侧工具栏，FPS 未取得有效帧样本前显示 `-- FPS`。
- loading 阶段的内容区、标题栏和右侧工具栏必须使用同一窗口背景色：Light `#F8F9FA`、Dark `#121212`，禁止混用 `colorScheme.surface` 造成色差。
- 投屏子窗口必须以隐藏状态创建，完成 Flutter 首帧后再显示；复用已有窗口前通过 `isFlutterReady` 握手确认 Dart Isolate 存活，握手失败时隐藏失效窗口并创建新窗口，禁止暴露或重复复用只有原生黑底的僵尸窗口。
- Android scrcpy 启动按 video、可选 audio、control 顺序连接 Socket，后序 Socket 较慢时必须保留已连接的前序 Socket。连接失败、连接超时或首帧超时属于可恢复启动故障，完整清理 Session 后自动重试一次，第二次仍失败才展示错误页。
- macOS 完全透明需要同时清除 `NSWindow.backgroundColor` 与子引擎 `FlutterViewController.backgroundColor`；只调用 `windowManager.setBackgroundColor(Colors.transparent)` 会保留 FlutterView 默认黑底。透明切换不得调用窗口定位或尺寸 API。
- 鼠标停留在标题栏或工具栏时暂停隐藏；进入对应固定槽位时恢复显示，离开整个窗口时立即隐藏。loading、失败和断开等非活跃状态不启用自动隐藏。
- 活跃投屏中，鼠标进入视频 Viewer 后延迟 300ms 隐藏标题栏和右侧工具栏，点击 Viewer 时立即隐藏；进入顶部或右侧固定透明槽位时重新显示。区域显隐不得改变窗口和 Viewer 尺寸。
- 投屏时长位于标题栏刷新按钮左侧，格式为 `MM:SS`，超过一小时后切换为 `H:MM:SS`；右侧工具栏底部以两行展示 FPS，上方为 `FPS` 标签、下方为帧率数值。两者从投屏 Session 首次展示开始按秒局部刷新。
- Android、HarmonyOS 和 AirPlay FPS 使用 Rust `Frame` 成功产出的可渲染帧累计值按秒做差；iOS USB 复用原生采集状态中的 FPS。不得使用前台 App 的 `dumpsys gfxinfo` FPS 代替投屏 FPS。
- Rust 帧计数使用 Atomic 累加并由 Dart 低频轮询，禁止为每帧建立 MethodChannel 事件或触发顶层窗口 rebuild。控件显隐不得调整原生窗口 Frame，也不得改变 Texture 的布局尺寸和触控映射。
- 窗口初始尺寸、横竖屏适配和拖拽缩放比例必须同时扣除右侧 32px 最窄工具栏宽度与顶部 30px 标题栏高度；缩放过程中按真实 Viewer 比例持续收敛，禁止把窗口总宽度直接作为视频宽度，否则竖屏会产生上下黑边。
- 从手机投屏窗口打开应用独立副屏时，不得停止当前主屏 Session；虚拟副屏优先使用手机物理分辨率与 DPI，例如 `1080x2376/480`，禁止直接使用受 `max_size` 缩放的解码帧尺寸。无物理信息时才按视频比例放大到长边至少 1920，最后回退 `1080x1920`。应用副屏工具栏隐藏 Home 与 Recent/Menu 键，避免 Task 离开目标应用。
- 应用副屏 Session 保存 scrcpy 创建的 virtual displayId；截图使用 `screencap -d <displayId> -p`，录屏使用 `screenrecord --display-id <displayId>`。应用副屏尚未取得 displayId 时必须提示失败，禁止回退抓取手机主屏；普通手机投屏继续沿用默认显示截图/录屏链路。

## 投屏标题设备信息悬浮层

- 单设备投屏入口 `openStandaloneMirrorWindow()` 优先使用 `deviceRegistryProvider` 中非空的 `customName`，未配置或清空名称时保留 `AdbDevice.displayName` 默认值（model，缺失时使用设备 ID）；按 `id`、`serial`、`connections` 匹配同一设备，覆盖 USB 与无线连接。
- 创建窗口时，原生窗口标题和 JSON 参数 `deviceName` 使用同一解析结果；子窗口标题栏复用该参数。该逻辑覆盖设备列表、控制面板与主窗口投屏快捷入口，批量投屏继续使用已支持别名的 `RegisteredDevice.displayName`。
- 名称在打开窗口时读取；已打开窗口仍使用启动参数，修改名称后重新打开生效。单 App 投屏继续保留应用名称。
- 回归检查：未配置名称、配置中文或含空格名称、清空名称后，分别从设备列表和控制面板打开投屏，确认窗口标题符合上述优先级；同一设备切换 USB/无线连接后验证别名，批量投屏与单 App 投屏检查既有标题行为。

- 鼠标进入投屏标题栏中的设备名称时，画面左上角展示设备名称、brand/model、分辨率与刷新率、RAM、系统版本和 `/data` 已用/总存储；鼠标离开设备名称后隐藏，投屏画面本身不触发展示。
- 数据统一读取 `deviceOverviewProvider(deviceId)`，优先显示 `SharedPreferences` 中的设备概览缓存，再异步刷新，禁止在 `onHover` 中重复执行 ADB command。
- 悬浮层使用 `IgnorePointer`，不能拦截投屏画面的点击、拖拽、右键返回或中键 Home；hover 状态只由设备名称的 `MouseRegion.onEnter/onExit` 更新，避免鼠标移动造成高频 rebuild。
- 信息卡颜色取自 `ThemeData.colorScheme`，字段名复用 l10n 的 `memory`、`storage` 和 `reading`，保证子窗口的 Dark/Light Mode 与中英文切换一致。

## HarmonyOS 工具栏控制

- HarmonyOS NEXT 投屏只复用 scrcpy 的视频渲染协议，系统控制必须走 `HdcService`，不能把 Android ADB command 或 scrcpy control message 直接发给鸿蒙设备。
- Android key code 到 OpenHarmony key code 的核心映射为：`HOME 3 -> 1`、`BACK 4 -> 2`、`VOLUME_UP 24 -> 16`、`VOLUME_DOWN 25 -> 17`、`POWER 26 -> 18`、`APP_SWITCH 187 -> RECENT 10011`。
- 剪贴板文本输入优先使用 API 18+ 的 `uitest uiInput text`，可覆盖当前焦点输入框和 Unicode 文本；旧系统命令失败时，仅对 ASCII 文本回退到 `uinput -K -t`。
- 物理屏幕亮灭分别使用 `power-shell wakeup` 与 `power-shell suspend`；截图优先使用 `uitest screenCap`，失败时回退 `snapshot_display`。
- 录屏通过系统 `com.huawei.hmos.screenrecorder.ServiceExtAbility` 启停，停止后使用 `mediatool query` 定位媒体文件；返回 `file://` URI 时先用 `mediatool recv` 导出到 `/data/local/tmp`，再通过 `hdc file recv` 下载到电脑。
- 前台窗口详情使用 `hidumper -s WindowManagerService -a '-a'`，Android 的 `dumpsys window` 只保留给 ADB 设备。
