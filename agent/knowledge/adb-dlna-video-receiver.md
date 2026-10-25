# Android 视频 DLNA 投到 macOS

## 目标与入口

- macOS 主窗口顶部的 DLNA 图标启停接收服务；Android 视频 App 与电脑处于同一局域网时，选择 `AnyDeck DLNA`。
- “设置 → 投屏设置 → Android DLNA 投屏名称”可以修改手机设备列表中的接收端名称；空白名称恢复为 `AnyDeck DLNA`。
- 只接收视频媒体地址与播放控制，不采集 Android 手机屏幕，也不影响现有 scrcpy / AirPlay 会话。
- AVPlayer 继续播放 MP4 与 HLS；新增内置 libmpv 回退窗口处理非 DRM DASH（独立音视频分片）及 AVPlayer 无法打开的媒体。平台特定鉴权、DRM 与弹幕仍不在通用 DLNA 能力内。

## 数据与控制链路

1. `lib/core/dlna/dlna_renderer_service.dart` 绑定 SSDP UDP `1900`，发布 `MediaRenderer:1`，并在收到 `M-SEARCH` 后回复设备描述地址。
2. 同一服务在固定 TCP `18583` 端口提供设备描述、`AVTransport`、`RenderingControl`、`ConnectionManager` 的 SCPD 与 SOAP 接口，避免手机缓存重启前的随机端口。
3. Android 控制端下发 `SetAVTransportURI` / `Play` / `Pause` / `Stop` / `Seek`。MP4/HLS 由 macOS `AVPlayer` 获取；`.mpd` 或媒体元数据标记为 `application/dash+xml` 时直接交给 libmpv，AVPlayer 失败时也自动回退一次。
4. `macos/Runner/DlnaPlayerBridgeService.swift` 通过 `any_deck/dlna_player` MethodChannel 接收播放命令，使用 `AVPlayerLayer` 在独立 macOS 窗口显示；视频保持原比例时，窗口与播放层以黑色填充留白。
5. libmpv 通过 `media_kit`、`media_kit_video` 和随包内置的 `media_kit_libs_macos_video` 在独立 Flutter 子窗口播放；URL 只经窗口 MethodChannel 传递，不放入启动参数或日志。播放、暂停、跳转、音量、静音、进度和关闭控制都由主窗口的 DLNA 服务路由。
6. 关闭播放窗口会停止播放器并通知 Dart；关闭 DLNA 接收开关会发送 SSDP `byebye`、释放 UDP/TCP 端口、清空订阅及两种播放器。
- 同一投屏会话切换视频时，`SetAVTransportURI` 只清空旧媒体，AVPlayer 与 libmpv 窗口保留原尺寸并显示加载状态；新视频首帧出现后隐藏加载层。抖音切视频可能先发送 `Stop`，接收端等待 5 秒：期间收到新的 `SetAVTransportURI` / `Play` 就取消关窗，超时才关闭窗口并清除媒体会话。用户主动关闭窗口立即结束当前会话；再次投屏需重新下发媒体地址。AVPlayer 与 libmpv 相互切换时会在新窗口可见后隐藏旧窗口，跨播放器不复用同一个原生窗口。
- 视频窗口可手动切换置顶：AVPlayer 的图钉位于 macOS 标题栏，libmpv 的图钉位于视频右上角；点击只改变当前窗口的 `floating` / `normal` 层级，不改变 DLNA 播放状态。置顶状态经主窗口服务在 AVPlayer 与 libmpv 间传递，切换媒体时沿用，关闭窗口或结束会话后恢复默认不置顶。图钉 Tooltip 复用现有中英文文案，并由主窗口在语言变化时同步到两种播放窗口。
- `RenderingControl` 的音量与静音由原生播放器分别保存；取消静音不会把先前音量重置为 100%，换片源后仍使用当前音量与静音状态。

## 名称设置与热更新

- `AppSettings.dlnaServerName` 默认 `AnyDeck DLNA`，使用 SharedPreferences 键 `settings.dlnaServerName` 持久化，并沿用设置广播同步到其他窗口。设置页与 iOS AirPlay 名称共用接收端名称编辑组件。
- 主窗口的 `DlnaRendererService.setServerName` 更新设备描述中的 `<friendlyName>`；XML 文本经转义，`UDN` 与 TCP `18583` 保持稳定。服务运行时发送 SSDP `byebye` 再发送 `alive`，不调用 `stop()`，因此不主动关闭正在播放的视频。
- 工具栏启用服务前读取当前设置，启动提示使用实际名称；macOS 原生播放器标题也通过 `setTitle` MethodChannel 更新。手机端可能缓存设备描述，需要重新搜索设备列表才能看到新名称。

## 协议与系统边界

- SSDP 使用 multicast `239.255.255.250:1900`，需要手机和电脑之间允许局域网发现与访问；不同 VLAN、访客 Wi-Fi、AP isolation 或 macOS 防火墙均可能阻断发现。
- 设备描述和 SOAP 使用 HTTP；`Info.plist` 中的 `NSAllowsArbitraryLoadsForMedia` 仅为 AVFoundation 媒体请求放开 ATS，普通网络请求不随之放开。该配置在 App Store 审核时需要说明用途。
- 服务没有增加 ADB 命令或后台进程；主窗口作为唯一 DLNA 服务 owner，名称设置沿用现有跨 Isolate 广播。
- `GetProtocolInfo` 与连接事件现在声明 MP4、HLS 和 `application/dash+xml`；子窗口用 `any_deck/dlna_fallback_events` 把关闭/失败状态回传主窗口。AVPlayer 首帧 15 秒未就绪时回退；原生失败日志只记录错误域、错误码和 HTTP 状态码，不记录签名 URL。
- libmpv 增加 macOS 包体和播放器内存开销；仅在 DASH 或 AVPlayer 失败时创建子窗口，关闭后释放 Player。设备端实际下发的 URL、鉴权和 DRM 仍决定能否播放，不能据此承诺与电视完全一致。
- 通用 DLNA 能否被 B 站特定版本识别，以及 B 站下发的 URL 能否由两种播放器播放，必须以真实 Android 手机与真实视频验证。成功编译和本地 DASH 样本验证不能证明具体受限视频可播。

## 黑屏排查记录

- 真机复现显示设备可发现、原生窗口黑屏。主窗口日志发现 `GetPositionInfo` 在原生通道返回整数零时抛出 `int` 到 `double` 的类型转换错误；现已按 `num` 接收后转为 `double`。
- 本地 H.264/AAC MP4 用支持 HTTP Range 的服务器测试时，原生窗口可播放且进度递增；不支持 Range 的简单 HTTP 服务器触发 `Operation Stopped`，因此接收端不能只凭 `PlayResponse` 判定视频播放成功。
- 重启进程可能让手机继续使用旧的随机 HTTP 端口。现将设备名称改为 `AnyDeck DLNA`、变更 UDN，并固定 HTTP 端口 `18583`。保留 SOAP 动作和 AVPlayer 错误日志，供真机复测定位媒体源问题；日志不记录完整媒体 URL 或签名查询参数。
- 新版在电脑上已监听 UDP `1900` 和 TCP `18583`，设备描述返回 `AnyDeck DLNA`。最初复测没有收到播放命令，原因是换用 `192.168.31.54` 的手机后，B 站投屏页仍显示旧会话；从该手机返回视频页并重新发起投屏后，接收端收到 `SetAVTransportURI` / `Play`，原生窗口出现实际 B 站视频画面。`GetPositionInfo` 两次读取分别为 `00:00:25` 与 `00:00:30`，时长 `00:27:43`，确认播放进度持续增长。
- 后续复测时手机投屏页虽勾选 `AnyDeck DLNA`，进度却停在 `00:00/00:00`；电脑端仍监听 UDP `1900`、TCP `18583`，设备描述正常，SOAP `GetTransportInfo` 返回 `NO_MEDIA_PRESENT`，`GetPositionInfo` 返回时长与进度 `00:00:00`。此时没有可播放媒体，因此播放器窗口不会出现；仍需通过实时请求日志区分手机未发 `SetAVTransportURI` 与请求被拒绝等情况。
- 2026-10-24 的另一次 B 站操作日志确认接收端在同一秒收到 `SetAVTransportURI` 和 `Play`，但仅记录了媒体域名，没有该媒体的格式、HTTP 响应或首帧状态，不能再将那一次无窗口归因于手机没发命令。新增的 AVPlayer 错误域/HTTP 状态及首帧超时日志用于复测区分。
- 同一视频切到别的视频后再投，旧实现可能在 `SetAVTransportURI` 等待旧窗口停止时就收到 `Play`，导致 `Play` 读取上一条地址。现先记录新地址和 generation，再串行清理旧播放器；`Play` 等待清理完成。原生 AVPlayer 失败事件携带 generation，旧媒体的迟到错误不会触发新媒体的 libmpv 回退。日志只记录 generation，不记录签名 URL。
- 2026-10-24 08:10 的现有运行进程记录到 B 站 `SetAVTransportURI`、`Play`、`Seek`，随后手机发来 `Stop`；用户反馈视频 A → B → A 后没有播放窗口且手机可以本地操作。`Stop` 之后日志只有设备发现请求，没有第二次 `SetAVTransportURI` / `Play`。这一次无窗口直接对应手机未下发新的播放命令，接收端没有可打开的新媒体；需要在 B 站投屏页断开后重新选设备确认其会话恢复路径。该进程在修复前启动，不能用来验证切源竞态修复。
- 用户在 B 站断开并重选同一设备后仍无窗口，接收端日志没有新的 SOAP 请求。手机通过 ADB 执行到电脑 `192.168.31.12:18583/device.xml` 的 HTTP GET 得到 `200 OK`，说明该时刻手机到接收端的 TCP 路径可达；仍需与爱奇艺等 App 对照，区分 B 站会话行为与接收端兼容性。
- 同一手机的抖音可以发现设备并读取 `device.xml`，选中设备后同样没有发 `SetAVTransportURI` 或 `Play`。随后对仍在运行的 AnyDeck 进程用本地 MP4 手动发送标准 SOAP `SetAVTransportURI` / `Play`，两次请求均返回 200；AVPlayer 通过 HTTP Range 读取媒体，`GetPositionInfo` 显示时长 30 秒、进度 11 秒。测试结束发送 `Stop` 并关闭临时 HTTP 服务器。这证明该进程在上一轮手机 `Stop` 后仍能接收控制并实际播放；手机 App 未下发播放动作是本轮无窗口的直接原因，但 App 为什么不下发仍需查其投屏会话或设备兼容条件。
- 2026-10-24 19:33 从 `25113PN0EC`（`192.168.31.128`）重试抖音时，手机 Logcat 的 `BDDLNASourceWrapper.detect` 报 `SocketTimeoutException`：它连接 `10.190.1.229:18583` 超时。该地址属于电脑的 `utun5` VPN，电脑 Wi-Fi `en0` 为 `192.168.31.12`，路由到手机走 `en0`。旧 SSDP 实现对所有 IPv4 网卡逐个回复 `LOCATION` 并逐个广播，导致手机选中无法访问的 VPN 地址；这解释了为何发现设备后没有进一步的 SOAP 播放命令。现按 macOS 路由选择对应网卡地址，单次 M-SEARCH 仅回复一个 `LOCATION`，组播广播也只公布组播出接口地址；地址缓存 30 秒且最多 32 条，停止服务时清空。20:06 真机复测确认 SSDP 公布 Wi-Fi 地址，并收到后续 SOAP 命令。
- 2026-10-24 晚间复测：修复 SSDP 地址后，抖音下发 `SetAVTransportURI` / `Play`，电脑视频持续播放，但手机停在“设备连接中”，持续轮询 `GetTransportInfo`，没有发送暂停或快进。接收端当时的 SOAP 响应为 `Transfer-Encoding: chunked`、无 `Content-Length`，且 AVTransport SCPD 将状态参数错误关联到普通字符串变量，`GetMediaInfo` 也丢弃发送端 metadata。现按 AVTransport:1 规范关联状态变量、保存并回读 `CurrentURIMetaData`，SOAP 响应按 UTF-8 字节长度写入 `Content-Length`。只修正 SCPD 与 metadata 后，手机仍显示连接中；再加入 `Content-Length` 的 Debug 构建后，`25113PN0EC` 显示绿色 `AnyDeck DLNA` 和实际播放进度，暂停按钮使接收端状态变成 `PAUSED_PLAYBACK`，快进按钮下发 `Seek`。这是本机真机结果，单轮验证不能排除手机缓存或视频差异对恢复的影响。
- 2026-10-25 鸿蒙 NEXT `nova 12 Ultra` 的 B 站真机复现：手机发送 `SetAVTransportURI` 后仅轮询 `GetTransportInfo` / `GetPositionInfo`，不发送 `Play`，因此接收端一直保持 `STOPPED` 且无窗口；其 SOAP `User-Agent` 为 `Linux/3.0.0 UPnP/1.0 Platinum/1.0.5.13`。同一投屏会话手动补发标准 `Play` 后，AVPlayer 首帧超时并切到 libmpv，电脑出现 B 站实际画面，手机进度从 `00:00/00:00` 恢复正常。现仅对该 Platinum 控制端在设置新媒体后首次查询播放状态时补发一次内部 `Play`；显式 `Play`、`Pause`、`Stop`、换源及结束会话均取消待补发状态，不记录带签名的媒体 URL。

## B 站手机端能力边界

- `192.168.31.54` 的 B 站投屏页在选择 `AnyDeck DLNA` 后，弹幕开关标注“官投专享”；倍速菜单中除 `1.0X` 外的选项也标注“官方投屏专享”；清晰度菜单中的 `1080P` 标注同样限制，`720P` 与 `360P` 可选。这是本次手机界面观察结果，不能把这些官方投屏功能算作通用 DLNA 已支持。
- 上述页面重启电脑 App 后仍显示旧会话且进度为 `00:00`，不代表接收端已在播放。需要返回视频页重新选择设备，并以电脑端实际窗口、声音和进度作为验收依据。
- 用户确认按“通用 DLNA 不显示弹幕并在产品中明确说明”验收；设置页 DLNA 名称说明和启动提示均使用与视频 App 无关的文案，不把弹幕列为可用能力。

## 已执行验证

- `flutter analyze --no-pub lib/core/dlna lib/features/dlna`：通过。
- `flutter test --no-pub test/core/dlna/dlna_protocol_test.dart test/core/dlna/dlna_player_bridge_test.dart`：6 项通过。
- `flutter build macos --debug --no-pub`：通过；已启动 Debug App 并验证 SSDP / HTTP 监听、设备描述及 B 站真机视频播放。声音、暂停、跳转与停止尚未逐项验收。
- 名称与控制增量：定向 `flutter analyze --no-pub` 通过；设置、名称编辑 Widget、协议、原生通道和 SOAP 控制共 13 项 `flutter test --no-pub` 通过；`flutter build macos --debug --no-pub` 通过。SOAP 集成测试覆盖运行时改名、设备描述、播放、暂停、继续、跳转、停止、音量与静音。该测试使用原生播放器 MethodChannel mock，不等同于听到真实声音或看到真机控制后的播放窗口变化。
- 运行中的 AnyDeck 已占用固定端口 `18583`，再次并行执行 SOAP 集成测试会因端口占用失败；这是测试环境冲突，不是断言失败。其余 10 项定向测试、定向分析、`git diff --check` 和包含黑色留白改动的 macOS Debug 构建通过；最新留白颜色及声音、控制仍待实机验收。
- DASH 回退增量：定向 `flutter analyze --no-pub` 通过；4 个 DLNA 测试文件共 9 项通过，SOAP 集成测试改用临时 HTTP 端口且不广播 SSDP，可与运行中的 AnyDeck 并行。`flutter build macos --debug --no-pub` 通过；随包 libmpv 对本地 HTTP MPD 成功读取音视频 `.m4s` 分片，播放进度超过 0.5 秒。尚未运行新构建进行 Flutter 子窗口和 B 站真机验收。
- 切源竞态增量：定向分析通过；SOAP 集成测试加入旧窗口停止期间立即收到新 `Play`，以及视频 A → B → A 的地址断言，测试通过；macOS Debug 构建通过。新构建的 B 站真机复测仍需运行中的 App 重启后进行。
- SSDP 多网卡修复：用模拟 `route -n get` 的单测确认 `en0` 的 `192.168.31.12` 优先于 `utun5` 的 `10.190.1.229`，无可用路由时不公布错误地址；DLNA 定向分析和相关测试通过。同时有 Wi-Fi 与 VPN 的 macOS 上已重启 AnyDeck，抖音重选设备后收到正确 `LOCATION` 和后续 SOAP 命令。
- 抖音控制状态兼容：AVTransport SCPD 与 metadata 回读的定向分析、SOAP 测试通过；SOAP 响应增加 `Content-Length` 后，定向测试验证不再使用 chunked 传输，macOS Debug 构建通过。`25113PN0EC` 真机显示已连接和进度，发送了 `Pause` 与 `Seek`；暂停后接收端 `GetTransportInfo` 返回 `PAUSED_PLAYBACK`。不同视频连续切换时，个别视频出现加载提示和进度归零，仍需单独检查媒体 URL 与播放器错误，不能据此断定所有视频均可播。
- 连续切视频窗口生命周期：DLNA 定向分析、11 项测试及 macOS Debug 构建通过；SOAP 测试确认 `Stop` 后窗口先保留、短时间内切源取消延迟关窗、等待期结束后清除会话且可重新投屏。`25113PN0EC` 抖音真机上下切视频后，新旧视频均在 macOS 的同一 `AnyDeck DLNA` 窗口 ID `25519` 播放；手机点“结束投屏”后该窗口关闭，DLNA 服务仍监听。加载层瞬间画面、手动关窗及结束后的手机重新选择设备尚未逐项目视验证；如果 App 超过 5 秒才下发新媒体，仍会按结束投屏关闭窗口。
- 鸿蒙 B 站状态轮询兼容：定向 `flutter analyze --no-pub`、SOAP 控制测试和 macOS Debug 构建通过。重启新构建后，同一台 `nova 12 Ultra` 的 B 站发送 `SetAVTransportURI`，约 2 秒后首次 `GetTransportInfo` 触发内部播放；电脑窗口实际出画面，手机显示 `20:46` 时长和持续变化的进度。手机暂停和继续分别到达 `Pause` / `Play`，均由新构建处理。本次视频由 AVPlayer 播放；其他视频格式、声音与切换视频仍需各自真机验证。
- 播放窗口置顶增量：`flutter analyze --no-pub lib/core/dlna lib/features/dlna lib/app/window/dlna test/core/dlna/dlna_renderer_control_test.dart` 无问题，`flutter test --no-pub test/core/dlna` 的 11 项测试通过，`flutter build macos --debug --no-pub` 通过；尚未在实际播放窗口点击图钉验证层级与切源后的状态。

## 真机验收清单

1. 同一 Wi-Fi 下点击 DLNA 图标，在 Android B 站视频页点 `TV`，确认列表可见 `AnyDeck DLNA`。
2. 选择接收端，确认视频和声音实际播放；分别验证 MP4 与 HLS 来源，以及暂停、继续、进度跳转、音量和停止。
3. 手机切换 Wi-Fi、电脑睡眠/唤醒、断开网络后重新启用，确认服务可重新被发现，无遗留端口占用。
4. 关闭播放器窗口与关闭 DLNA 开关，确认手机端状态更新、电脑停止播放。
5. 验证 macOS Light/Dark 下图标状态与中英文文案；确认 Android scrcpy 与 iOS AirPlay 原有操作不受影响。
6. 用可公开访问的非 DRM DASH MPD 验证 libmpv 子窗口首帧、音画同步、暂停/继续、Seek、音量/静音、关闭与重新投屏；再用此前失败的 B 站视频对照 `AVPlayer failed`、`starting libmpv fallback`、`libmpv first frame rendered` 或脱敏错误日志。验证失败/窗口关闭后没有残留子窗口或播放资源。
7. 分别在 AVPlayer 与 libmpv 播放窗口点击图钉，切换到其他 App 确认置顶，再取消置顶确认恢复；切换视频及播放器验证状态沿用，结束投屏后重新投屏确认默认不置顶。
