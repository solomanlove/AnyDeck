# iOS 投屏控制

更新：2026-10-07。目标：先完成 macOS + iPhone 6s（当前连接设备为 iOS 15.8.8）的可验证实现；高版本 iPhone、Windows、Linux 后续验证。本文是实现与验收记录，不能将编译通过写成真机功能通过。

## 1. 结论与两个 PoC

投屏画面和输入控制必须分开选择技术。视频能显示，不代表设备允许注入触摸；WDA 控制正常，也不代表截图流可以达到流畅视频效果。

| PoC | 视频 | 控制 | 本轮状态 |
| --- | --- | --- | --- |
| PoC 1：较新 iOS 原生服务 | CoreDevice ScreenStream，研究 HEVC 视频与硬件解码 | CoreDevice HID 服务 | 保留调研路径和验收项；按用户要求推迟到高版本真机阶段，未集成、未验证 |
| PoC 2：旧 iOS / macOS USB | CoreMediaIO 开放 iPhone 采集设备 → AVFoundation → CVPixelBuffer → Flutter Texture | 已签名 WDA Runner → XCTest → USB 转发 → 异步 WDA HTTP | 本轮实现。10 月 7 日已取得 6s 原生视频帧，用户确认 AnyDeck 可以投屏；WDA 已签名安装，Session/窗口几何/Home 请求真机 PoC 通过，窗口点击和滑动仍待验收 |

本轮只落地 PoC 2，不能说“两套方案都已实测”。iPhone 6s 不用 PoC 1 验证，也不尝试用 iOS 17+ tunnel 提示解决 iOS 15 的 WDA 未启动问题。

本轮定位是 **USB 视频 + 基础自动化控制**。WDA 完整手势在鼠标抬起后才提交；它不等于 Android scrcpy 的实时连续触摸，游戏、拖动跟手、多指手势不在本期承诺内。流畅度必须实测，不承诺 60 FPS。

## 2. 原方案的问题

1. 截图中的关键错误是 `127.0.0.1:8100 connection refused`：电脑本地没有可用 WDA 监听/转发。启动 go-ios agent 的提示是另一条通用警告，不能据此断言 iPhone 6s 需要 iOS 17 tunnel。
2. 原 BLE 实现只改状态和发送模拟事件，没有真实蓝牙 HID 广播、配对、协议和输入注入。显示“已连接”不能证明控制成功。本次删除 Dart 服务、Rust 模块、FFI 入口及两处 UI 按钮。
3. 原投屏反复截图、JPEG 编解码、Dart 缓冲解析、`Image.memory` 更新，不能作为高帧率视频链路。原固定 3333 端口还会按端口结束其他进程；本次删除该投屏路径和清理方式。独立“截图”功能保留。
4. 原控制使用全局固定 8100，部分请求没有 Session；阻塞 Rust HTTP、CLI 和模拟 BLE 混用。多设备、多窗口没有统一会话归属，且 HTTP/W3C 失败可能被当作成功。

## 3. 本轮实现

### 3.1 视频

- `macos/Runner/IosUsbCapture.swift`：开启 `kCMIOHardwarePropertyAllowScreenCaptureDevices`，使用 IOKit 确认目标物理 USB UDID，优先精确匹配采集 ID；若 AVFoundation 返回 UUID，仅在一台物理 USB iOS 设备和一个 Apple iOS muxed 屏幕候选时关联，多设备歧义明确失败；不按名称选第一台摄像头。
- 独立串行队列配置和启动采集，另一串行队列接收帧。输出 BGRA、IOSurface/Metal 可用的 CVPixelBuffer，丢弃迟到帧；只持有最新帧，主线程刷新通知合并。
- `IosUsbCapturePlugin.swift` 为每个 Flutter Engine 注册独立 Texture；真实首帧到达才返回成功，15 秒未到首帧失败。窗口关闭停止采集，拒绝旧会话回调污染新会话。
- Dart `IosUsbMirrorService` 仅传控制消息和 Texture ID，不搬运视频字节。`activeIosMirrorProvider` 为兼容窗口现有 `int?` 接口，数值现在是 Texture ID，旧 `port/getPort` 名称不再代表网络端口。
- 500 ms 读取一次宽高、平均采集 FPS、最新帧年龄及错误。运行时异常、断开或连续 10 秒没有帧会结束投屏。FPS 是采集计数/运行时长，不是 Flutter 实际呈现帧率。
- macOS 摄像头权限用于 AVFoundation USB iPhone 采集。当前保留旧 `muxed` 设备枚举以兼容旧 iPhone；新 SDK 会报告弃用警告。
- 暂不采集音频，不启用网络视频回退。Windows/Linux 明确返回本期仅支持 macOS，不能悄悄退回截图流并称为原生视频。

### 3.2 控制

`IosWdaHost` 在主窗口唯一持有每台设备的 Runner、iproxy、WDA Session。子窗口通过单接收方 `WindowMethodChannel` 调用；Texture 仍属于各窗口自身引擎。

启动顺序：

1. 查询已安装应用；自动选择唯一名称包含 `WebDriverAgent` 且 Bundle ID 以 `.xctrunner` 结束的 Runner。找不到或不唯一均报前置条件错误，不猜测设备/Runner。底层允许显式 `bundleId`。
2. `ios image auto --udid=<UDID>` 准备 Developer Disk Image（60 秒超时）；iOS 15 XCTest 需要它。
3. 分配动态本地端口，用 `iproxy --source 127.0.0.1 --local --udid <UDID> <port>:8100` 转发。源码核对发现 go-ios v1.2.0 的 `forward` 固定绑定 `0.0.0.0`，因此不用于本轮桌面转发。
4. `ios runwda --bundleid=<RunnerID> --testrunnerbundleid=<RunnerID> --xctestconfig=WebDriverAgentRunner.xctest --udid=<UDID>` 启动测试 Runner。
5. 轮询 `/status`，创建 `/session`，读取 point 窗口尺寸与方向；以上成功才标记“控制已就绪”。

`IosWdaHttp` 使用 Dart 异步 HttpClient，请求预先编码 UTF-8 并设置字节级 Content-Length（WDA 不接受 chunked 请求）；支持分块响应并验证 HTTP、W3C、JSONWP 错误。单请求 8 秒超时，响应上限 8 MiB。所有控制操作统一路由，失败不回退到别的后端。

同一设备不积压输入，跨设备独立；几何查询在多窗口间合并，输入等待进行中的只读查询。取消启动、Runner/iproxy 退出、窗口主动结束会话、应用正常退出时释放资源；日志有界，只结束自身创建的进程，不按端口杀 PID。异常强制杀死桌面进程不保证能执行清理；启动中的 DDI 短命令最多等待其超时，取消后不会继续启动 Runner。

### 3.3 坐标与界面

- 控制页与投屏窗口复用“启用/停止/取消控制”入口及状态，默认仅投屏。已移除 BLE 入口和虚假连接状态。
- 按 `BoxFit.contain` 的真实视频区域映射坐标，黑边点击无效；例如 750×1334 视频对应 375×667 point，不能直接把像素当 point。
- 方向或尺寸在一次手势中改变即丢弃该手势；视频与 WDA 的横竖方向尚未同步时暂停输入。
- 点击、滑动通过一次 W3C `/actions` 发送。支持 Home、音量、锁屏和向当前焦点输入文字；剪贴板按钮也调用同一 Session。键盘持续按键、滚轮和多指触摸尚未实现。
- 新增文案同时提供中英文；状态/错误颜色跟随主题，视频区域使用黑底。

## 4. PoC 2 操作步骤

### 4.1 前置条件

macOS、完整 Xcode、go-ios（本机 1.2.0）、iproxy（本机 2.1.1）、可签名的 Apple Developer Team、iPhone 数据线。手机解锁并“信任此电脑”；电脑端允许相机权限。iOS 15 没有后续 iOS 的 Developer Mode 开关，不按新版截图引导开启。

```bash
brew install libusbmuxd
# 同时确认 ios 和完整 Xcode 已安装
xcodebuild -version
ios list --details
```

单纯 `ConnectionType: Network` 不满足本轮 USB 视频要求；有设备列表不等于有可采集屏幕。

### 4.2 单独验证视频，不启动 AnyDeck

```bash
bash script/ios_usb_poc.sh --list
bash script/ios_usb_poc.sh '<iPhone-UDID>' 30
```

脚本编译并复用产品的 Swift 采集器，嵌入权限说明；输出帧数、宽高、采集平均 FPS、帧年龄，不保存屏幕内容。无真实帧退出非零。动态画面、旋转和 30 秒连续采集都需要在手机上实际操作后观察。

### 4.3 准备 WDA

```bash
# 仅验证编译，不选择签名、不安装、不启动桌面项目
bash script/ios_wda_setup.sh --build-unsigned

# 用户指定 Team 后执行，签名、构建并安装到指定设备
bash script/ios_wda_setup.sh '<iPhone-UDID>' '<10位DeveloperTeamID>'
```

脚本固定 Appium WDA 源码 revision `d17782422d55ff1e5e0ceb74eb1fd509cc0c35b6`，不追随 master；iOS deployment target 为 15.0。临时源码中的 Runner Bundle ID 改为 `com.anydeck.WebDriverAgentRunner.<team>`，构建结束删除临时源码，产物留在 `~/Library/Caches/AnyDeck/ios-poc/`。签名模式允许 Xcode 为用户明确选定的 Team 更新 provisioning/注册该设备；不自动选择多个本地身份之一。

安装后在 iPhone 的设备管理中信任开发者证书。签名过期需要重新部署。WDA 的构建成功与该版本 XCTest 在 iOS 15.8.8 上可运行是两个验收项。

### 4.4 单独验证控制，不启动 AnyDeck

```bash
# 默认只检查 Runner/转发/Session/窗口几何并停止
ANYDECK_IOS_POC_UDID='<iPhone-UDID>' \
  flutter test test/ios_wda_device_poc_test.dart

# 明确允许 PoC 按一次 Home
ANYDECK_IOS_POC_UDID='<iPhone-UDID>' ANYDECK_IOS_POC_HOME=1 \
  flutter test test/ios_wda_device_poc_test.dart
```

未设置 UDID 时真机测试默认 skip；不得把 skip 计为真机通过。完成两条链路后，再人工打开 AnyDeck 验证组合效果。

## 5. PoC 1 与跨平台后续方向

| 方向 | 后续要验证的内容 | 边界 |
| --- | --- | --- |
| CoreDevice ScreenStream + HID | 服务发现、配对/tunnel、HEVC 解码、HID touch 序列、方向与取消、断线恢复 | pymobiledevice3 有相关源码，但不能把“CoreDevice 属于较新 iOS”推成所有 iOS 17+ 都支持这两个具体服务；必须按具体机型/版本探测 |
| Windows/Linux 旧 iOS 视频 | AirPlay 接收（例如 UxPlay）或 ReplayKit Broadcast Extension + WebRTC，再与 WDA 独立组合 | AirPlay 需手机主动选择接收端；ReplayKit 需手机端 App/Extension 和用户启动广播；两者都不自动获得全局触摸注入能力 |
| WDA 跨平台控制 | 复用主机 Session 状态机、USB 驱动/配对与转发；在 Windows/Linux 上启动已签名 Runner | 首次 iOS 工程签名/构建通常仍需要 macOS/Xcode，本轮没有验证这两个宿主 |
| Apple iPhone Mirroring | 可作较新 Apple 生态体验对照 | 不覆盖 iPhone 6s，也不是本项目的跨平台 API 方案 |

PoC 1 的通过条件：指定设备上同时读到真实视频帧和实际 HID 输入结果；记录协议、版本、30 分钟帧率/内存/断连恢复数据后，再决定是否替换 WDA。现在不增加第二个未验证的控制按钮。

许可证：本次没有将 pymobiledevice3（GPL-3.0）、UxPlay（GPL-3.0）或 iproxy（GPL-2.0-or-later）源码合并/链接到 Apache-2.0 项目。iproxy 是用户本地独立 CLI 依赖；后续若随产品再分发其二进制，需同时落实对应许可证、源码提供等义务，不能仅因独立进程就忽略分发要求。WDA 为独立签名 Runner，也须保留上游许可证。

## 6. 本次验证与剩余验收

| 检查 | 记录 |
| --- | --- |
| macOS Debug 编译 | 已通过；未启动 AnyDeck 桌面项目 |
| WDA 未签名构建 | 固定 revision、Xcode 26.3、iOS 15.0 target 编译通过；未签名产物不能安装 |
| Rust 单元测试 | 19 通过、1 个本地视频测试按原配置 ignored |
| Dart 定向检查 | 变更 Dart 文件 analyze 无问题；iOS 测试集 + Harmony 投屏回归 90 项通过、1 项真机 PoC 因未设置 UDID 跳过；包含双设备动态端口、Session 和自有进程回收的本地假 CLI 测试；随后 USB 原生桥接/生命周期/坐标 7 项、错误展示 8 项通过（部分与前述测试重叠） |
| USB 独立探针 | 10 月 7 日真实连接后修正 UDID/采集 UUID 匹配；20 秒采集 1173 帧，约 59.2 FPS，752×1334，无采集错误。属于原生采集结果，非 Flutter 呈现帧率 |
| 真机 WDA | 个人 Team 签名安装成功；用户信任后启动服务，修复 chunked HTTP 请求被拒绝的问题；Session、窗口几何和 Home 请求真机 PoC 通过，投屏窗口点击/滑动仍待人工验收，详见 8.1、8.2 |
| 高版本/Windows/Linux | 延后，未验证 |

组合验收建议（均为目标，不是实测结果）：

1. 6s 竖屏、横屏、黑边、窗口缩放各验证至少 20 次点击；旋转中不误点。
2. 连续滚动列表 30 分钟，记录采集 FPS、实际呈现帧率、CPU/RSS、输入响应 P50/P95；无持续增长的帧/输入队列。视频目标先达到稳定 25–30 FPS，再以实测决定是否进一步优化。
3. Home、文字、音量、锁屏后解锁恢复、拔插 USB、拒绝权限、WDA 崩溃、首次签名失败分别验证。
4. 主/子窗口都能观察同一控制状态；两台设备互不串控，关闭与重启后无自有 Runner/iproxy 残留。
5. Android scrcpy、Harmony 投屏及原有 iOS 应用/截图/进程入口回归。两设备原生同时采集、实际窗口交互和明暗主题仍需要人工验收。

## 7. USB 失败复查（2026-10-07，重新连接前）

用户反馈 USB 连接后仍无法投屏。本次检查不能证明已修复该真机问题：

- 找到了 10 月 6 日 22:40、22:44 和 10 月 7 日 00:40 的投屏子窗口启动记录，但旧实现未记录原生采集失败详情，无法由这些日志确定当时失败在哪一步。
- 10 月 7 日复查时 `ios list --details` 返回空列表，IOUSB 未发现 iPhone。独立探针对目标 UDID 返回 `iosUsbDeviceMissing`、`stage=discovering`、`frames=0`；枚举结果仅为电脑摄像头和已有虚拟摄像头。这描述当前检查环境，不能反推用户先前没有插线。
- 补充 `ios-video` 日志：请求启动、收到首帧、异常/断帧结束；原生错误携带采集阶段、枚举设备 ID/媒体类型/连接状态/挂起状态、相机授权状态。Texture 注册返回 0 必须失败，不再进入投屏成功状态。
- 错误文案使用 iOS 专属提示，避免误套 Android USB 调试教程。日志位于应用支持目录 `com.github.anydeck/logs/`；支持界面的本地日志导出。
- 用户重新连接并保持手机解锁后，先运行独立视频探针取得真实帧，再确认 AnyDeck 当前进程是新构建版本、相机授权和 Texture 显示。当前运行进程不会因重新 build 自动加载新 Swift 代码；需用户完整退出/重新启动后验证。
- **USB 视频不依赖 WDA、签名 Team 或 8100 端口**。在出现真实帧之前，不把部署 WDA 当作投屏故障的解决方法。

## 8. USB 真机定位与修复（2026-10-07，重新连接后）

重新连接 iPhone 6s / iOS 15.8.8 后，USB 注册表与 go-ios 均能识别目标设备，但原生 PoC 仍报 `iosUsbDeviceMissing`。实际枚举证明：

- go-ios / IOKit 返回 40 位设备 UDID；AVFoundation 返回另一个 UUID。
- 此采集设备的 `modelID` 为 `iOS Device`、manufacturer 为 `Apple Inc.`、`muxed=true`、`video=false`。只枚举 video 或把 uniqueID 当作 UDID 均会漏掉真实屏幕。
- 此前“两个标识必然相同”的假设错误；根因已由真机复现确认，不是重新部署 WDA 可以解决的问题。

新增 `IosUsbDeviceSelection`，按物理 USB 身份与采集候选唯一性关联。仅适用于本轮单台 UUID iPhone 的明确场景；有多个 USB iOS 设备或多个候选而无法精确关联时，显示“只连接目标 iPhone”提示，不能任意取第一个或按手机名称猜测。精确 ID 匹配的旧接口仍保留。

PoC 另修正权限顺序：先等待 macOS Camera 授权，再启用采集并开始计时。首次系统权限等待期间曾得到 0 帧，授权完成后复测取得真实视频。产品原生插件已在开始采集前请求权限；CLI 使用宿主进程的 TCC 身份，不能把 CLI 授权等同于 AnyDeck 授权。

验证：

- 与产品复用同一 Swift 采集器，20 秒实测 1173 帧、约 59.2 FPS、752×1334，`stage=streaming`、`error` 为空。没有保存手机屏幕内容。
- 最终 30 秒复测采集 1695 帧，约 57.0 FPS，752×1334，最新帧年龄约 5 ms，仍无采集错误。新 Debug 构建通过，Dart 定向 analyze 无问题，USB 桥接/坐标/错误展示 14 项回归通过。
- 设备选择 7 项无真机回归覆盖 UUID、旧 ID 精确匹配、多设备歧义、无 USB、错误 UDID 和普通摄像头排除。
- 新 Swift 文件加入 Xcode 编译；需完整重启 AnyDeck，Flutter 热重载不能替换已加载的原生插件。
- 用户随后确认 AnyDeck 已可以投屏；新进程的窗口日志记录 `USB first frame ready`。旋转、长时间稳定性及 WDA 控制仍待验收；不能仅由采集 FPS 推断端到端延迟。

```bash
bash script/ios_usb_poc.sh --test-selection
bash script/ios_usb_poc.sh '<iPhone-UDID>' 30
```

### 8.1 视频恢复后，控制未启用的真机检查

2026-10-07 用户反馈“可以投屏了，但不能控制”。再次通过 go-ios 查询该 USB iPhone 的已安装应用，13 个应用中没有 WebDriverAgent Runner。当前控制实现必须先安装已签名的 Runner，再点击“启用控制”；只插 USB 不会自动获得 XCTest 输入能力。

本机存在多个 Apple Development 签名身份。证书显示名称中的括号标识不能直接当成 Team ID，应核对证书 Subject OU 或 Xcode Team。用户随后明确选择个人 Team `C7PX48FL76`，已运行第 4.3 节脚本：

- `xcodebuild build-for-testing` 签名构建成功，`ios install` 报告成功；再次查询手机应用，确认 `com.anydeck.WebDriverAgentRunner.c7px48fl76.xctrunner` 已安装。
- 本次 embedded provisioning profile 包含目标 UDID，Team 正确，有效期至 **2026-10-14 13:44:13（Asia/Shanghai）**。本次个人签名需要到期重新部署，不代表永久安装。
- 两次独立控制 PoC 均在 go-ios `com.apple.instruments.server.services.processcontrol` 建立通道阶段超时，随后 `broken pipe` 退出；WDA 尚未监听，未建立 Session。
- Xcode `test-without-building` 交叉检查报告 `0xE8000084 / This device is no longer connected`；同一时段 IOKit 与 go-ios 仍能枚举 USB 设备。因此不能直接断言数据线已拔出，也未证明是 WDA HTTP 或触摸坐标问题。
- 下一步需手机解锁并确认开发者证书信任及 Runner 是否能手动打开，再检查调试服务与启动兼容性。尚未发送 Home 或点击，不把签名安装记为控制通过。

后续可更换 Team：使用新 Team 重新签名安装并在手机上信任。现有脚本的 Bundle ID 带 Team 后缀，旧、新 Runner 可能并存；需移除旧 Runner 或明确指定目标 Bundle ID，避免自动选择出现多个候选。USB 视频不依赖签名 Team。

### 8.2 信任证书后的 WDA 请求修复

用户确认已信任开发者证书，Runner 能手动打开并显示空白界面。再次运行同一真机 PoC，调试服务启动成功，但创建 Session 返回 `HTTP 400: Transfer-Encoding is not supported`。空白 Runner 界面本身不代表 XCTest/WDA 已启动，必须检查服务响应。

根因：Dart `HttpClientRequest.write(jsonEncode(body))` 在没有 Content-Length 时发送 chunked 请求，当前 WDA 的 HTTP 服务拒绝这种请求体。修复为先编码 UTF-8，设置实际字节长度，再 `add(payload)`；无请求体也显式设置长度 0，分块响应解码保持原逻辑。

验证结果：

- 新增固定长度请求回归，覆盖 Session、中文/emoji 文本和无 body 的 Home POST；HTTP/Host/生命周期 9 项本地测试通过，定向 analyze 无问题。
- 同一 iPhone 6s 上，默认真机 PoC 通过：Runner 启动、USB 转发、Session 创建、窗口几何读取、停止及资源回收。
- 启用 `ANYDECK_IOS_POC_HOME=1` 后再次通过，WDA 接受 Home 请求。尚未将这些结果扩大为投屏窗口触控坐标、滑动和文字输入全部通过。
- 本次修复只涉及 Dart 请求逻辑；已运行的 AnyDeck 需加载新代码，再点击“启用控制”进行窗口人工验收。测试结束主动停止其自有 Runner/iproxy，不保留独立 PoC 进程占用设备。

## 9. 上游依据

- [Apple QuickTime：录制连接设备的视频](https://support.apple.com/en-in/guide/quicktime-player/qtp356b55534/mac)：验证 macOS USB 采集路径的产品可行性；不是对本项目帧率的保证。
- [Appium WebDriverAgent](https://github.com/appium/WebDriverAgent/tree/d17782422d55ff1e5e0ceb74eb1fd509cc0c35b6)：本次固定源码、XCTest Runner 与 HTTP 接口。
- [go-ios v1.2.0](https://github.com/danielpaulus/go-ios/tree/v1.2.0)：DDI/Runner 启动；[forward.go](https://github.com/danielpaulus/go-ios/blob/v1.2.0/ios/forward/forward.go) 中绑定所有网卡的实现是改用 iproxy 的直接依据。
- [libusbmuxd iproxy](https://github.com/libimobiledevice/libusbmuxd/blob/master/tools/iproxy.c)：USB/UDID 选择与 loopback 监听参数、许可证。
- [pymobiledevice3 CoreDevice 服务](https://github.com/doronz88/pymobiledevice3/tree/114671735f19ae4310c2aec6fb0d954f5295c04a/pymobiledevice3/remote/core_device)：后续原生视频/HID 研究线索。
- [UxPlay](https://github.com/FDH2/UxPlay)、[Apple ReplayKit](https://developer.apple.com/documentation/replaykit)：后续跨平台视频候选。
