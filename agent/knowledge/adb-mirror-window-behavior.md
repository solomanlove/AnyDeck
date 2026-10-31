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
- `AppToast` 通过 `OverlayEntry` 统一渲染在当前窗口顶部居中位置，不依赖 `ScaffoldMessenger`，适合投屏子窗口、设置弹窗返回后的提示、拖拽安装/上传结果、截图/录屏结果、剪贴板发送失败、返回键和音量键长按提示。
- 新增投屏提示时优先按语义选择 `AppToastType.success`、`error`、`warning`、`info`，只有需要兼容旧调用时才使用 `isError` 参数。

## Android 投屏断线自动换线（2026-10-29）

### 目标与连接选择

- USB 投屏的 `adb shell` server 进程异常退出后，立即重新执行 `adb devices -l`，使用同一手机当前已在线的其他 transport 恢复投屏。传统 TCP/IP 与 Android TLS/mDNS 无线调试均支持，不等待子窗口已停用的设备心跳，也不读取旧 IP 直接重连。
- `core/scrcpy/mirror_transport_resolver.dart` 保存初始硬件身份：USB 使用设备序列号，网络连接在宿主创建时通过现有 `AdbWirelessProbe.serial` 读取 `ro.serialno / ro.boot.serialno`。候选必须处于 `device` 状态并回读到同一硬件序列号，不能按型号、列表顺序或历史 IP 猜测身份。
- 排除本轮已失败的连接，候选优先 USB、普通 TCP、TLS/mDNS；mDNS 名称中的空格保持完整。每次恢复都重新查询列表，支持 Wi-Fi 动态端口变化。列表查询最多 3 秒，单候选属性查询最多 2 秒，新列表与候选扫描共享 6 秒预算；网络初始身份读取独立进行。
- 没有同设备在线替代连接时结束恢复并展示原有停止/失败界面。不自动启用无线调试，不调用 `adb connect` 连接历史地址，不增加常驻 ADB 轮询。

### 会话与窗口生命周期

- `ActiveEmbeddedMirrorNotifier` 通过 `mirrorDisconnectedProvider` 区分异常退出/启动失败与主动停止。异常发生时并行开始旧资源清理与新连接查询；实际新建会话前仍须等待旧 Texture、Rust 会话、server 与 forward 的清理完成。
- 启动请求合并为单一 Future，generation 让主动停止前的进程退出回调失效；启动中停止或 Provider 已销毁时，迟到的会话立即释放，不再更新 Texture 状态。主动停止、刷新和正常窗口关闭不会触发自动换线。
- `app/window/mirror/android_mirror_transport_host.dart` 在原生窗口内按新 transport 重建 `MirrorWindowContent`，统一重绑 Viewer、触控、截图、录屏和设备操作，保留原设备名称及应用副屏启动参数。状态提示复用现有 `startingMirrorService` 与 Theme；iOS、HarmonyOS 不进入该宿主。
- 同一轮恢复每个失败 transport 最多尝试一次，避免 USB/TCP/TLS 之间反复循环；会话持续运行至少 3 秒后发生新的断线时，重新开始一轮选路。关闭窗口会取消解析，并丢弃迟到的查询结果。
- 重建内容时，Controller 缓存停止入口和 Android service，卸载阶段不再通过 WidgetRef 查找 Provider；旧首帧等待、启动重试与窗口比例适配任务检查 disposed，避免旧内容在换线后重新拉起旧会话或通知已释放的 UI。

### 自动与真机验证

- 新增 21 项选路/会话/宿主测试，覆盖 USB→TCP→TLS、USB 重新可用、DHCP 地址复用、离线/未授权过滤、带空格的 mDNS ID、串号回退、重复事件、并发启动、旧资源清理顺序、全部候选失败终止、恢复中关闭窗口及 Provider 销毁。
- 与剪贴板、窗口比例、AirPlay 路由、断线状态页、ADB 截图及屏幕电源回归合计 74 项通过；状态页测试补充真实项目 Theme fixture，避免缺少 `AppThemeColors` 时空值异常。9 个修改/新增 Dart 文件定向 analyze 通过；全量 analyze 仍在其他文件报告 39 项既有 warning/info。

```bash
flutter test test/mirror_transport_resolver_test.dart \
  test/android_mirror_transport_host_test.dart test/mirror_clipboard_sync_test.dart \
  test/mirror_window_aspect_and_rotation_test.dart test/airplay_mirror_window_target_test.dart \
  test/mirror_error_info_test.dart test/adb_service_test.dart \
  test/adb_screenshot_display_test.dart test/device_power_actions_test.dart
```

- 只读真机选路验证：SM-F9710 的 USB `R5GL6378JMH` 与 `192.168.1.244:5555` 同时在线；调用修改后的 resolver 并排除 USB，在约 1546ms 内选中 TCP 地址，回读序列号仍为 `R5GL6378JMH`。该验证没有拔线、停止用户正在运行的投屏或新建真机会话。
- 按项目约定未启动/重新构建 App。真实 USB 拔线后的画面、音频、窗口状态与工具栏操作仍需手动验收：先建立同机 USB+无线连接，USB 投屏后拔线，确认原窗口自动恢复；再断开当前无线连接验证另一个在线通道，并检查主动停止及恢复中关窗不会自行重启。

### 实时优选与当前通道标签（2026-10-29）

- 原实现只在异常断线时重新选路；现在健康的 TCP/Wi-Fi 投屏也监听设备事件。USB 重新上线并通过同机硬件身份校验后自动优先切回 USB；Wi-Fi 投屏期间普通 TCP 上线也会升级，顺序为 USB → TCP → Wi-Fi。同级或更低优先级连接变化不会重建健康会话。
- `mirror_transport_devices_provider.dart` 主窗口复用已有 `AdbDeviceTracker`，每个投屏子 Isolate 共享一条仅 ADB 的 `track-devices -l` 事件流，先提供当前快照，再推送变化。不启用子窗口心跳、iOS/HDC 轮询或高频列表命令；订阅释放后关闭监听。Tracker 还会终止窗口关闭后才启动完成的迟到进程。
- 连接变化做 350ms 防抖，优选探测直接使用事件快照，只查询高优先级候选的序列号；断线恢复仍重新查询实时列表。事件快照中的 iOS/HarmonyOS 不参与 Android 候选选择。选择期间出现新事件会重新评估，迟到结果或已主动停止的会话不能触发切换。
- 坏 USB 启动失败后可以回退原健康 TCP，不会在 USB 与 TCP 间不断抢占；只有该 USB 真正离线后再次上线，才解除本轮失败限制。所有通道切换均等待旧会话释放，再按新 ID 重建画面和操作，属于短暂重连，不是正在使用的 ADB socket 原地迁移。
- `mirror_transport_type.dart` 统一优先级与显示类型，沿用项目对 USB、传统 TCP 和 TLS/mDNS/动态端口无线调试的识别约定。设备信息悬浮卡的名称右侧显示 `USB 投屏 / TCP 投屏 / Wi-Fi 投屏`；标签取自当前会话绑定的 `deviceId`，不使用注册表中可能不同的 preferred ID。概览加载中、读取失败时也能显示，iOS/HarmonyOS 不猜测 Android 通道。
- `widget/mirror_device_name_heading.dart` 复用名称与通道标题，长名称省略时保留完整标签；使用 Theme ColorScheme、共享圆角及中英文字符串。无新增设置项或跨窗口 MethodChannel，主题与语言继续沿用原有同步。
- 102 项相关测试通过，覆盖 USB→TCP→USB 及标签同步、Wi-Fi→TCP、同级不切换、身份不匹配、坏 USB 回退、主动停止、优选中关窗、共享事件流与迟到进程回收、中英文/明暗主题/窄卡片及概览异常；14 个变更 Dart 文件定向 analyze 无问题。全量 analyze 仍为其他文件的 39 项既有 warning/info。
- 只读验证还确认本机 `adb track-devices -l` 的初始输出使用 4 字节十六进制长度头，当前 Tracker 的事件解析与实际 CLI 输出一致。未启动或重建桌面 App，实际 USB 热插拔的画面恢复、短暂加载及标签位置仍待窗口验收。
- 同机只读优选验证：以三星当前 TCP `192.168.1.244:5555` 作为会话通道，传入最新设备快照，约 1550ms 后返回更优的 USB `R5GL6378JMH`，类型为 `usb`；只执行查询和序列号校验，没有切换用户正在运行的真实投屏。

```bash
flutter test test/mirror_transport_resolver_test.dart test/android_mirror_transport_host_test.dart \
  test/mirror_transport_devices_provider_test.dart test/mirror_transport_badge_test.dart \
  test/mirror_device_info_overlay_test.dart test/mirror_clipboard_sync_test.dart \
  test/mirror_window_aspect_and_rotation_test.dart test/airplay_mirror_window_target_test.dart \
  test/mirror_error_info_test.dart test/adb_service_test.dart \
  test/adb_screenshot_display_test.dart test/device_power_actions_test.dart
```

### 换线加载提示文字样式（2026-10-30）

- 用户反馈“正在启动投屏服务...”显示为大号红字和黄色双下划线。原因是换线遮罩位于 `MirrorWindowContent` 的 `Scaffold` 外层，原 `ColoredBox` 不提供默认文字样式，导致 `Text` 继承 `MaterialApp` 的警示样式（48 号红字、黄色双下划线）。
- `AndroidMirrorTransportHost` 的遮罩改用 `Material`，独立提供当前 Theme 的 `bodyMedium`，背景继续使用 `colorScheme.surface`，文案继续复用 `startingMirrorService`，中英文与明暗主题同步生效。
- `test/android_mirror_loading_style_test.dart` 保留 `MaterialApp → AndroidMirrorTransportHost → Scaffold` 的真实层级，用假 ADB 阻塞查询以检查重连中状态，验证实际 `RichText` 字号、字重、颜色及无下划线；覆盖中英文、明暗主题和 320×420 窗口。查询结束后遮罩正常消失。
- 新增 4 项样式测试与原换线测试合计 21 项通过，2 个相关 Dart 文件定向 analyze 无问题；未启动桌面 App。本次仅修复遮罩样式，不调整连接优先级或音视频会话。

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

- 标题栏投屏计时由 `MirrorSessionDuration` 复用；计时文本及两侧留白共同响应鼠标悬停，Tooltip 显示本地化“投屏时间”，Android/HarmonyOS 与 iOS AirPlay 标题栏保持一致。

- 单设备投屏入口 `openStandaloneMirrorWindow()` 优先使用 `deviceRegistryProvider` 中非空的 `customName`，未配置或清空名称时保留 `DiscoveredDevice.displayName` 默认值（model，缺失时使用设备 ID）；按 `id`、`serial`、`connections` 匹配同一设备，覆盖 USB 与无线连接。
- 创建窗口时，原生窗口标题和 JSON 参数 `deviceName` 使用同一解析结果；子窗口标题栏复用该参数。该逻辑覆盖设备列表、控制面板与主窗口投屏快捷入口，批量投屏继续使用已支持别名的 `RegisteredDevice.displayName`。
- 名称在打开窗口时读取；已打开窗口仍使用启动参数，修改名称后重新打开生效。单 App 投屏继续保留应用名称。
- 回归检查：未配置名称、配置中文或含空格名称、清空名称后，分别从设备列表和控制面板打开投屏，确认窗口标题符合上述优先级；同一设备切换 USB/无线连接后验证别名，批量投屏与单 App 投屏检查既有标题行为。

- 鼠标进入投屏标题栏中的设备名称时，画面左上角展示设备名称、brand/model、分辨率与刷新率、RAM、系统版本和 `/data` 已用/总存储；鼠标离开设备名称后隐藏，投屏画面本身不触发展示。
- 数据统一读取 `deviceOverviewProvider(deviceId)`，优先显示 `SharedPreferences` 中的设备概览缓存，再异步刷新，禁止在 `onHover` 中重复执行 ADB command。
- 悬浮层使用 `IgnorePointer`，不能拦截投屏画面的点击、拖拽、右键返回或中键 Home；hover 状态只由设备名称的 `MouseRegion.onEnter/onExit` 更新，避免鼠标移动造成高频 rebuild。
- 信息卡颜色取自 `ThemeData.colorScheme`，字段名复用 l10n 的 `memory`、`storage` 和 `reading`，保证子窗口的 Dark/Light Mode 与中英文切换一致。

## 手机剪贴板入口

- Android 投屏工具栏的剪贴板图标打开独立 Dialog，复用 `DeviceClipboardView`；使用统计弹窗移除原剪贴板 Tab。原有 `T` 按钮仍负责电脑文本输入手机。
- `MirrorClipboardButton` 接收当前投屏的 ADB deviceId，支持主屏和应用副屏；HarmonyOS 与 iOS 不展示 Android 剪贴板监听入口。
- 面板不自动开始读取，用户点击开始后由 `deviceAuxiliaryProvider` 创建独立 Rust 辅助会话。关闭 Dialog 后 autoDispose 取消订阅、定时器与辅助会话，不停止投屏 Session；记录只保存在当前面板内存中。
- 复用已有中英文文案、Theme 和设备版本门槛；不新增跨窗口广播。原工具栏文本输入按钮及前台窗口摘要拆分为独立文件，使工具栏保持 500 行以内。
- 回归路径：Android 投屏打开面板，开始监听、手机复制文本、刷新、复制到电脑、清空、停止；关闭重开检查记录清空和投屏持续。检查中英文、Light/Dark、窄窗口弹框及设备断开状态。
- 验证边界：针对性静态检查与剪贴板测试；未启动 App，仍需真机验收。完整 `device_auxiliary_test.dart` 中 API 31 摄像头版本门槛的 4 个用例因 ADB/日志 pending Timer 失败，属于此次未修改的摄像头测试路径。

### 投屏双栏剪贴板（2026-10-24）

- Android 投屏剪贴板入口改为双栏 Dialog，分别展示电脑和当前手机的文本剪贴板；顶部“自动同步”默认开启。电脑内容每 500ms 读取一次，手机内容由现有 Rust 辅助会话推送；只在内容变化时同步，并抑制自己写入产生的回环。弹窗关闭即停止轮询、释放辅助会话。
- 电脑写入手机使用当前投屏 control socket 的 scrcpy 4.0 `SET_CLIPBOARD`（type 9、sequence 0、paste flag、UTF-8 长度及正文），文本上限为 256 KiB 减 14 字节；手动“粘贴到设备”请求 Android 粘贴键（Android 7+），自动同步仅更新设备剪贴板，不向焦点输入框注入文字。手机写入电脑使用 Flutter `Clipboard.setData`。
- 活跃 Android 投屏子窗口没有主窗口 Registry SDK 缓存时，剪贴板辅助会话可以凭活跃投屏状态通过 UI 版本门槛；Rust 启动时继续回读 SDK。HarmonyOS、iOS 投屏不显示此入口。仅同步文本，系统清空手机剪贴板不一定推送事件，面板可能显示最近一次收到的内容。
- 验证：`test/mirror_clipboard_sync_test.dart` 覆盖协议字节、首条手机文本、回环抑制、手动粘贴、关闭自动同步、子窗口 SDK 缺失及双栏渲染；定向 `flutter analyze --no-pub` 和 `git diff --check` 通过。未运行桌面 App，仍需 macOS + Android 真机检查剪贴板变化、焦点粘贴、断连及明暗主题。

## HarmonyOS 工具栏控制

- HarmonyOS 投屏工具栏隐藏“前台窗口”和“手机设置”入口；平台判断使用 `controller.isHarmony`，Android 工具栏继续显示这两个入口。

- `hoscrcpy-sidecar.jar` 启动握手必须解析完整 JSON 的 `ready` 与 `port` 字段，不能依赖无空格的固定字符串。等待端口期间同时监听 stderr 和 process exit：设备离线、HDC 路径异常或 Java 失败时直接返回真实原因；只有进程仍存活且始终未报告端口时才判定 timeout。失败后先正常终止，再以 `SIGKILL` 兜底，避免残留 sidecar。
- HarmonyOS 工具栏电源按钮打开“唤醒屏幕 / 息屏休眠”菜单，复用控制 Tab 的 `HdcService.setScreenPower`，分别执行 `power-shell wakeup` / `power-shell suspend`。不缓存或猜测设备亮灭状态，避免实体按键与主窗口操作导致状态不同步；命令执行期间禁用重复点击。验收路径：投屏电源菜单息屏后再次打开菜单唤醒，并在实体按键息屏后验证唤醒；设备断开时显示命令失败反馈。鼠标路径录制、回放、暂停状态在窄工具栏内必须纵向排列，禁止使用 `Row` 横向溢出。
- 投屏窗口右侧“手机设置”按钮在 HarmonyOS 下展示“系统页面跳转”，按系统设置、Wi-Fi、应用管理排列；具体页优先使用 HDC/Want action，商用系统拒绝隐式启动或目标 action 不存在时回退 Settings 首页，不展示 Android 专属 density、font scale 与 layout helper。
- 前台窗口弹框只展示从 WindowManagerService dump 中提取的页面、Bundle、Ability 与窗口名称；无法解析时展示友好提示，不直接把整段 hidumper 原始输出暴露给用户。
- HarmonyOS NEXT 投屏只复用 scrcpy 的视频渲染协议，系统控制必须走 `HdcService`，不能把 Android ADB command 或 scrcpy control message 直接发给鸿蒙设备。
- Android key code 到 OpenHarmony key code 的核心映射为：`HOME 3 -> 1`、`BACK 4 -> 2`、`VOLUME_UP 24 -> 16`、`VOLUME_DOWN 25 -> 17`、`POWER 26 -> 18`、`APP_SWITCH 187 -> RECENT 10011`。
- 剪贴板文本输入优先使用 API 18+ 的 `uitest uiInput text`，可覆盖当前焦点输入框和 Unicode 文本；旧系统命令失败时，仅对 ASCII 文本回退到 `uinput -K -t`。
- 物理屏幕亮灭分别使用 `power-shell wakeup` 与 `power-shell suspend`；截图优先使用 `uitest screenCap`，失败时回退 `snapshot_display`。
- 录屏通过系统 `com.huawei.hmos.screenrecorder.ServiceExtAbility` 启停，停止后使用 `mediatool query` 定位媒体文件；返回 `file://` URI 时先用 `mediatool recv` 导出到 `/data/local/tmp`，再通过 `hdc file recv` 下载到电脑。
- 前台窗口详情使用 `hidumper -s WindowManagerService -a '-a'`，Android 的 `dumpsys window` 只保留给 ADB 设备。
