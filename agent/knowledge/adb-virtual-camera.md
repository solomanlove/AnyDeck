# AnyDeck macOS 系统摄像头

## 实现状态与范围

2026-11-07 新增实验性系统摄像头链路。功能代码、Extension Target、Flutter 入口及自动测试已接入；**尚未进行已签名扩展激活、手机真实采集或会议应用画面验收**。能够构建、系统中出现摄像头名字、显示占位画面，都不能代替真实视频验收。

- 宿主门槛：macOS 13+；设备门槛：Android 12 / API 31+，沿用已授权的 ADB 连接。
- 输出名称：`AnyDeck Camera`。首版格式固定为 1280×720、BGRA、30 fps。
- 只提供视频；会议软件继续使用其选择的 Mac、耳机或外接麦克风。
- 当前同一手机的本地摄像头预览与系统摄像头**互斥，没有共享采集会话**。启用共享前停止当前预览；跨 Flutter Engine 的原生租约拦截其它窗口的占用。
- 此功能不依赖屏幕投屏窗口，不会把手机屏幕画面送入会议。

## 用户入口与生命周期

Android 设备 → 控制 → 摄像头 → “用作 Mac 摄像头”：

1. 点击安装摄像头扩展，按 macOS 提示批准；只有系统实际发现 AnyDeck Camera 后才视为可用。安装请求完成和系统设备就绪分别判断。
2. 选择前置或后置镜头，显式打开“提供给 Mac 应用”。仅记录本次进程内的选择，不在应用启动时自动开启采集。
3. Zoom、FaceTime 等应用选中 AnyDeck Camera 后，Extension source 的需求属性触发主程序采集。没有消费者时保留已启用状态，停止占用手机镜头。
4. 关闭摄像头弹窗仅停止本地预览及 Flutter 状态轮询，已启用的系统摄像头继续由应用级原生单例管理。菜单栏提供前后镜头切换与停止入口。
5. 关闭共享、卸载扩展、退出 AnyDeck、设备或视频流异常时回收会话。最后一个消费者停止后有 2 秒宽限，避免摄像头选择器造成频繁重启。

UI 每秒查询一次原生状态，单次超时 5 秒；查询不执行 ADB 命令。页面销毁会取消查询计时器与等待，但不会发送共享停止命令。迟到查询通过 revision 隔离，不能覆盖用户更新的状态。

## 视频与控制链路

```text
Android scrcpy-server 4.0 摄像头 H.264
→ ADB forward / Rust 独立会话
→ VideoToolbox / CVPixelBuffer（IOSurface）
→ Swift VirtualCameraFrameFormatter / CMSampleBuffer
→ CoreMediaIO sink queue
→ Camera Extension consumeSampleBuffer
→ source send / Zoom、FaceTime 等客户端
```

| 模块 | 职责 |
| --- | --- |
| `lib/core/virtual_camera/` | MethodChannel 状态、启用配置及可取消轮询 |
| `lib/features/control/widgets/virtual_camera_controls.dart` | 安装、停用、镜头选择与共享开关 |
| `lib/core/scrcpy/embedded_camera_backend.dart` | 本地预览的 acquire/release 原生租约，阻止跨窗口镜头抢占 |
| `macos/Runner/VirtualCamera/VirtualCameraPlugin.swift` | 所有 Flutter Engine 的统一入口与退出清理 |
| `VirtualCameraCoordinator.swift` | 用户启用与下游需求状态机、有限重试、旧会话退出等待 |
| `VirtualCameraRustSession.swift` | 复用 Rust C ABI 采集、状态、帧数与像素接口 |
| `VirtualCameraFrameFormatter.swift` | 固定格式转换、等比留黑边、host clock 时间戳 |
| `VirtualCameraSink.swift` | 按设备 UUID 与固定 stream 名称发现 source/sink，读取需求，向有界队列供帧 |
| `VirtualCameraActivation.swift` / `VirtualCameraMenu.swift` | 系统激活回调与菜单栏操作 |
| `macos/AnyDeckCameraExtension/` | Provider、Device、source/sink、帧校验和过期帧清理 |
| `macos/CameraShared/VirtualCameraContract.swift` | 主应用与扩展共用标识、视频格式及需求属性 |

主程序先确认用户启用，再读取 source stream 自定义属性 `4cc_dmnd_glob_0000`；当前通过 NSString `"0"` / `"1"` 表示是否存在下游需求，不把 sink 写入者计为会议消费者。设备、source、sink UUID 保持稳定，升级不能随意更换。

帧数未变化时不重复转换；尺寸和像素格式已经匹配时直接包装现有像素，否则通过 CoreImage 等比缩放到720p并留黑边。转换池限制最多 6 个缓冲，sink 队列深度为 2，满队列丢帧，避免积压扩大延迟。Extension 只保留最近一帧，格式不匹配或无 IOSurface 的帧不接受，超过 1 秒没有新帧改用占位画面。

采集/供帧状态由原生串行队列独占访问。需求探测间隔 0.5 秒，采集时调度 30 fps；启动首帧等待最多 75 秒，运行后超过 3 秒无新帧视为失败。失败后间隔 3 秒有限重试，最多 3 次；切换镜头或重启共享重置重试计数。先停止旧 Rust 会话，等待其清理完成或达到 65 秒上限后释放，防止切换过程中两路竞争摄像头。

## 安装、签名与打包

Extension bundle ID 为 `com.github.anydeck.camera-extension`，随 Runner 嵌入：

```text
AnyDeck.app/Contents/Library/SystemExtensions/
  com.github.anydeck.camera-extension.systemextension
```

- 签名构建使用 `CameraDebugProfile.entitlements` / `CameraRelease.entitlements`，包含 `com.apple.developer.system-extension.install` 与 `com.apple.security.application-groups`；不改变主应用现有非 sandbox 配置。
- 主应用与 Extension 共用 `ANYDECK_CAMERA_ENTITLEMENTS_PREFIX`，默认均为空：主应用使用原有 entitlements，Extension 使用仅含 App Sandbox 的 `Extension.entitlements`，两者保留 ad-hoc 签名。设置 `ANYDECK_CAMERA_ENTITLEMENTS_PREFIX=Camera` 时，主应用使用 `CameraDebugProfile.entitlements` / `CameraRelease.entitlements`，Extension 使用原有 `CameraExtension.entitlements`；由用户提供 `DEVELOPMENT_TEAM`、`CODE_SIGN_IDENTITY` 与对应 provisioning，不自动选择本机其它组织证书。
- Extension 使用 App Sandbox，App Group 为 `group.com.github.anydeck.camera`，Mach service 为 `group.com.github.anydeck.camera.service`。
- 正式使用必须配置有效开发团队、主应用及 Extension 的签名与所需 provisioning。当前仓库没有配置可用团队签名。
- 用户从 `/Applications/AnyDeck.app` 发起激活请求，按系统要求由管理员批准。系统返回需要重启时，UI 保留该状态，不把旧版本可见设备当成新版本激活成功。
- `CODE_SIGNING_ALLOWED=NO` 仅用于构建验证，生成的包不表示能被系统批准或发布；签名和公证应在交付流程中另行验证。

### 普通构建签名失败修复（2026-11-07）

原配置仅让主应用按前缀切换 entitlements，Extension 的 Debug / Release / Profile 始终使用含 App Group 的权限文件，继承项目的 `CODE_SIGN_IDENTITY=-` 后触发 `has entitlements that require signing with a development certificate`。修复后 Extension 同步按前缀选取权限，不需要全局关闭 `CODE_SIGNING_ALLOWED`。

| 构建模式 | 主应用权限 | Extension 权限 | 使用边界 |
| --- | --- | --- | --- |
| 默认本地构建 | 原有调试/发布权限 | App Sandbox | 用于普通调试与本地打包，不能激活系统摄像头扩展 |
| `ANYDECK_CAMERA_ENTITLEMENTS_PREFIX=Camera` | 扩展安装权限与 App Group | App Sandbox 与同一 App Group | 仍需有效开发团队、证书与 provisioning，才能继续验证激活 |

`Embed Native Dylibs` 阶段设置 `alwaysOutOfDate=1`，明确每次执行，由 Cargo 判断 Rust 源码是否需要增量编译，避免漏掉源码或架构变化，并消除未声明 outputs 的构建警告。

修复仅涉及 Xcode 构建权限选择和脚本阶段调度；不新增依赖、运行时采集任务或跨窗口状态。后续回归应确认普通 Debug 能构建，以及正式签名后的安装权限和主应用/Extension App Group 一致；真实扩展激活仍按下方验收表执行。

## 自动验证与实际验收

已执行的 Flutter 聚焦用例共 23 项通过：原预览 9 项、系统摄像头状态 4 项、UI/本地化 7 项、跨窗口租约 3 项。覆盖显式启用、交接失败不启动、重复点击、迟到状态隔离、关闭弹窗持续共享、Android 版本门控、中英/明暗/小窗口、租约拒绝及启动取消。定向静态分析无问题。

```bash
flutter test --no-pub test/virtual_camera_test.dart \
  test/virtual_camera_widget_test.dart \
  test/virtual_camera_preview_lease_test.dart test/camera_preview_test.dart
bash script/test_virtual_camera_native.sh
python3 -m unittest discover -s test/script -p test_camera_extension_signing.py -v
```

原生脚本以合成像素和假会话验证格式、帧过期、消费者生命周期及资源释放：8 项 Host 检查和 Extension 校验通过。完整 Runner Debug 使用 `CODE_SIGNING_ALLOWED=NO` 构建通过。上述检查不启动 AnyDeck、不安装扩展、不访问真实镜头。

签名回归 3 项测试通过：通过 Xcode 解析 Debug / Release / Profile 的主应用与 Extension 配置，校验默认权限不含 App Group / 安装权限，Camera 模式保留完整权限；另在临时目录以默认 ad-hoc 签名单独构建 Extension，并使用 `codesign --verify --strict` 验证，防止只做全局禁签构建而遗漏本次错误。现有 macOS App policy 与 Rust 构建范围回归各 1 项通过，Xcode 工程和 entitlements 的 `plutil -lint` 通过。未启动 AnyDeck，也未重新验证完整 Runner 构建或真实摄像头激活。

本次全量 `flutter analyze --no-pub` 无 error，但因 38 项现有 warning / info 返回非零；这些报告均位于与 HEAD 一致的 Dart 文件中，本次不改动相关代码。

仍需完成以下实际验收，全部通过后再把此能力标为已验证：

| 场景 | 验收条件 |
| --- | --- |
| 签名与首次安装 | 主应用、Extension 签名与权限有效；管理员批准后 `systemextensionsctl list` 显示 activated/enabled；记录实际激活版本 |
| 扩展升级 | 包内版本、系统激活版本及重启后版本一致；拒绝批准或待重启时状态正确 |
| 首帧与连续画面 | QuickTime、FaceTime、Zoom 选中后出现手机实时镜头；移动镜头确认持续更新，不能用占位帧判成功 |
| 前后镜头 | 弹窗和菜单栏切换均正确，比例与方向正常，不串旧画面、不重复启动 |
| 窗口生命周期 | 关闭弹窗、隐藏主窗口后会议仍有画面；菜单栏停止及退出 AnyDeck 后手机释放摄像头 |
| 多客户端 | 两个视频应用同时使用时都有画面；关闭一个不停止另一个，全部关闭后释放镜头 |
| 本地预览互斥 | 当前窗口或其它窗口已有预览时按约定交接或明确拒绝；失败后能重新使用 |
| 断线与占用 | 拔线、Wi-Fi 断开、镜头被手机 App 占用时明确失败/占位，不停留敏感旧帧；重连后可重新开启 |
| 长时间稳定性 | USB、Wi-Fi 分别运行至少 10 分钟，检查真实帧率/端到端延迟、内存是否持续增长及退出后的会话/端口残留 |
| 原功能回归 | 屏幕投屏、应用融合投屏、本地前后/双摄预览和麦克风监听仍能按原方式启停 |
