# Knowledge Index (AI 需求与知识库索引)

本索引用于管理 AnyDeck 项目内已实现的需求与业务机制知识库 (Knowledge)。所有的 AI 助手在进行二次开发或优化相关需求前，应根据本索引的指引，优先调取对应模块的知识库文档。

## 知识库列表

### 1. 业务与机制知识 (Business & Mechanisms)

| Knowledge | 中文名 | 状态 | 用途 | 关联模块 |
| --- | --- | --- | --- | --- |
| `adb-memory-performance-controls` | 内存与后台性能控制 | active | 性能采样 worker、日志/终端与 PID 进程、可见性轮询、截图保存背压、SQLite 展示索引及原生 Texture 帧门控 | `core/performance/`, `core/logcat/`, `core/terminal/`, `core/apps/`, `features/ios/`, `features/screenshot/`, `macos/Runner/` |
| `adb-screenshot-image-editing` | 截图图片编辑 | active | 右上角编辑入口、形状/画笔/马赛克与遮盖、撤销重做、原图坐标、PNG 合成、会话互斥与资源释放 | `features/screenshot/` |
| `adb-mirror-whiteboard` | 投屏白板本地标注 | active | 画笔入口、颜色/撤销/清空、Texture 透明画布、设备输入阻断、窗口生命周期及回归边界 | `app/window/mirror/`, `features/control/` |
| `adb-settings-manual-removal` | 设置页说明书入口移除 | active | 记录设置页“软件说明书”入口、弹框和专用文案的移除范围及回归验证 | `features/overview/`, `features/widgets/`, `app/l10n/` |
| `adb-svg-assets` | SVG 与位图资源加载 | active | 本地 SVG/PNG 公共组件、品牌图片接入、加载失败回退与验证边界 | `app/widget/`, `features/devices/`, `features/overview/` |
| `adb-ui-theme-system` | UI Theme 统一机制 | active | 统一品牌色、Light/Dark 语义色、边框、圆角与顶部轻提示，记录轻提示首帧/遮挡时的 Overlay 清理与回归，并明确固定业务色和 Painter 注入边界 | `app/theme/`, `app/widget/`, `app/window/`, `features/` |
| `adb-local-diagnostic-logs` | 控制台与本地诊断日志 | active | 运行异常采集、关键日志筛选、跨窗口汇总、滚动文件、本地日志导出、工具栏图标交互统一与搜索自适应布局及验证边界 | `core/logging/`, `app/window/console/`, `features/developer/` |
| `adb-github-feedback` | GitHub Issues 意见反馈 | active | 设置页标题与正文编辑、环境信息快照、分类草稿保留、长正文复制兜底、网页模板及验证边界 | `features/feedback/`, `core/process/`, `.github/ISSUE_TEMPLATE/` |
| `adb-local-apk-inspector` | macOS Android 安装包分析与安装 | active | APK/APKS/AAB/XAPK 文件关联与离线分析、Protobuf 模块/分包清单、签名信息、APK 安装队列、临时目录回收与回归边界 | `core/apk/`, `features/apk/`, `app/window/apk/`, `rust/apk_inspector/` |
| `adb-unified-app-detail-view` | 应用详情统一展示模型与 UI | active | 记录本地 APK 与已安装应用如何转换为统一 `AppDetailViewData`，并复用同一分栏、概要与 Tabs Widget | `app/widget/`, `features/apk/`, `features/apps/` |
| `adb-terminal-pty` | 终端 PTY 与 root 提示符 | active | 记录 Android 真实 shell 回显与 root 提示符、HarmonyOS 本地 `$` 输入提示符、流式换行处理与回归边界 | `core/terminal/`, `features/terminal/` |
| `adb-remote-controller` | Android 与 HarmonyOS 共用遥控器 | active | 记录四方向扇区交互、中心 OK、ADB/HDC 键码路由及验证边界 | `features/widgets/`, `features/control/`, `core/device_actions/` |
| `adb-app-permissions` | 应用权限分类与批量撤销 | active | 记录动态 / 静态 / 未知权限分类、当前用户隔离、批量撤销与回读结果、共享面板及回归验证 | `core/apps/`, `features/apps/` |
| `adb-apps-context-menu` | 应用单项右键菜单 | active | Android 列表/网格的 13 项右键操作、顶部单项工具栏移除、目标应用与批量勾选隔离、断线和重复操作拦截及验证边界 | `features/apps/`, `test/` |
| `adb-app-native-library-copy` | 应用原生库名称复制 | active | 记录应用详情原生库 Tab 的 `.so` 库名 Clipboard 复制、统一反馈与原生库规则拆分边界 | `features/apps/` |
| `adb-app-default-icons` | 应用图标缺失时的平台回退 | active | 记录应用与进程真实图标优先、文件缺失或损坏时按 Android/HarmonyOS 展示本地默认资源，以及资源来源和验证边界 | `features/apps/`, `features/processes/`, `assets/brand/` |
| `adb-harmony-app-analysis` | HarmonyOS 已安装应用独立分析 | active | 记录 HDC `bm dump` 能力探测、独立的开发厂商与开发者/组织字段、HarmonyOS 专属详情页、失败不跳转和 Android 链路隔离 | `core/apps/`, `features/apps/` |
| `adb-app-signature-details` | 应用签名证书详情 | active | 记录已安装应用当前/历史 signer、X.509 证书字段、MD5/SHA-1/SHA-256 指纹及 Android Helper DEX 数据链路 | `core/apps/`, `features/apps/`, `tool/android_helper/` |
| `adb-usage-companion` | 手机使用统计、位置记录与 ADB 历史同步 | active | 可见授权、系统统计口径、位置前台服务、手机离线库、分页游标与 SQLite 事务、内嵌地图底图、图标复用及验证边界 | `core/usage/`, `features/apps/`, `tool/usage_companion/` |
| `adb-device-rust-sessions` | 屏幕投屏、摄像头、麦克风与手机剪贴板 Rust 底座 | active | 屏幕投屏、VideoToolbox 硬解、AudioQueue 自恢复、音频断流有限重试、无线积压降分辨率/码率、触控注入、摄像头、麦克风与剪贴板 Rust 底座 | `core/scrcpy/`, `features/apps/`, `rust/device_bridge/` |
| `adb-device-rust-sessions-test` | Rust 设备会话回归验证 | active | 自动验证结果、平台门槛、生成视频帧解码与真机回归清单 | `test/`, `rust/device_bridge/` |
| `adb-embedded-camera` | 内嵌摄像头预览 | active | scrcpy camera 参数、独立会话/端口、原生 Texture 复用、手动启停及销毁回收、macOS 限制与回归边界 | `core/scrcpy/`, `features/apps/`, `rust/device_bridge/` |
| `adb-virtual-camera` | macOS 系统摄像头 | experimental | Camera Extension source/sink、720p30、按下游需求采集、菜单栏及预览租约互斥；本地 ad-hoc 与 Camera 权限隔离，签名激活与会议真实画面尚未验收 | `core/virtual_camera/`, `macos/Runner/VirtualCamera/`, `macos/AnyDeckCameraExtension/` |
| `adb-cert-management` | 证书管理机制 | active | 记录用户证书与系统证书（Root 权限，包含 Android 10+ 内存挂载与 Conscrypt APEX 挂载）的导入机制与 adb 命令设计 | `control/` (控制面板) |
| `adb-emulator-management` | 模拟器启动诊断与配置详情 | active | 记录启动诊断、ADB 授权与离线状态、定向重连/关闭、冷启动与 SDK 环境、标题工具栏、复用系统版本平台 Tab、详情及中英文配置搜索 | `core/emulator/`, `core/providers/`, `features/devices/` |
| `adb-desktop-platform-chrome` | 跨平台桌面窗口与工作区 UI | active | macOS 原生按钮避让、Windows 主窗口标题栏、Linux 原生装饰、子窗口标题同步、公共主题表面与宿主验证边界 | `app/window/`, `features/overview/`, `linux/runner/` |
| `adb-desktop-window-shortcuts` | 桌面窗口与软件快捷键 | active | 主窗口、通用操作与投屏统一按键录入、自由修饰键、跨组冲突与旧键释放、持久化广播、子窗口动作转发、退出确认与 macOS 菜单边界 | `app/shortcuts/`, `app/settings/`, `app/window/`, `features/overview/` |
| `adb-tabs-features-principles` | 各 Tab 功能与实现原理指南 | active | 梳理概览的平台字段分流、产品名称与型号独立展示、折叠机内外屏分辨率、电量/充电状态、内存占用与容量卡布局，以及控制、鸿蒙应用右键清除缓存、鸿蒙文件页单一路径导航、日志紧凑视图时间配色、终端、鸿蒙进程 CPU/内存采样及进程操作、网页调试、布局分析、性能监控、网络/端口转发等 Tab 的功能设计与底层原理 | `dashboard/` (主面板各 Tab) |
| `adb-forward-port-mapping` | Android/HarmonyOS 正向端口转发 | active | 记录网络页正向规则的用途、ADB/HDC 命令、列表过滤、端口校验及验证边界 | `core/network/`, `core/providers/`, `features/network/` |
| `adb-wifi-connection-principles` | ADB 无线调试连接与断开原理 | active | 记录 USB 自动准备监听、2 秒等待与就绪检测、实时 Wi-Fi IP、列表与概览 IP 同源展示、在线 TCP 地址优先与旧缓存修复、网段提示与主机网络快照同步、TCP 优先和目标 mDNS 回退、TLS 切换恢复、双语状态及手动连接指南 | `core/adb/wireless/`, `core/providers/`, `features/devices/` |
| `adb-lan-device-sharing` | 局域网 Android 单设备共享 | experimental | 分享码与临时 TLS、固定 transport 的 ADB Bridge、接收方本机 ADB、Forward/Reverse、单接收者与撤销、来源标识及真机验收边界 | `core/device_share/`, `features/devices/` |
| `hdc-wireless-debugging` | HarmonyOS HDC 无线调试增强 | active | 记录身份绑定历史、USB/TCP 双通道、USB 回读 IP、退避重连、Remote HDC Server 与开发板 UART 边界 | `core/harmony/wireless/`, `core/providers/`, `features/devices/` |
| `hdc-harmony-overview-hardware-network` | 鸿蒙设备概览硬件与网络信息 | active | 记录 HDC 读取当前 SSID、精确型号处理器映射和内核版本解析及回退边界 | `core/harmony/`, `core/providers/`, `features/overview/` |
| `devices_manager` | 设备唯一标识判断机制 | active | 记录设备发现/连接命名约定、DiscoveredDevice.id 命令路由、HDC 在线状态过滤、ADB/HDC 同地址优先级、hardware serial 多连接合并，以及 iOS 列表型号/版本与离线缓存 | `dashboard/devices/` (设备控制行) |
| `adb-mirror-window-launcher-script` | 投屏子窗口启动文件生成脚本 | active | 记录 `script/generate_mirror_window_launcher.sh` 如何复用 `multi_window <windowId> <json>` 参数生成可执行启动文件 | `script/`, `app/window/mirror/` |
| `adb-mirror-window-behavior` | 投屏独立窗口行为机制 | active | 记录投屏窗口设备名称优先级、比例适配、横竖屏无断流渲染、Android USB/TCP/TLS 断线恢复与事件驱动优选、当前投屏通道标签与重连提示样式、设备信息悬浮层与计时 Tooltip、手机剪贴板入口、单 App 工具栏规则，以及 HarmonyOS HDC 控制映射 | `app/window/mirror/`, `core/scrcpy/`, `rust/device_bridge/`, `core/harmony/` |
| `adb-fusion-app-mirroring` | Android 融合投屏 | active | Android 14+ 默认开关、App 副屏与主屏路由、标题栏 App 图标点击与加载反馈、手机操作占位与恢复、窗口与音频复用、动态尺寸及 DPI、图库缩放过渡和真机回归边界 | `features/apps/`, `app/window/mirror/`, `core/scrcpy/` |
| `ios投屏控制` | iOS 投屏控制方案与 PoC | active | macOS/iPhone 6s 原生 USB Texture + WDA、USB/AirPlay 共用投屏窗口与来源标识、窗口比例贴合、部署探针及真机验收边界 | `core/ios/`, `core/airplay/`, `app/window/mirror/`, `macos/Runner/`, `script/` |
| `ios-mirror-principles` | iOS 投屏与设备管理机制 | active | 记录 go-ios 集成、USB/Network 连接类型与旧 Rust 库兼容、概览读取与型号规格边界、USB 投屏、截图镜像恢复、进程应用关联、扩展宿主 Bundle ID、多窗口及验证边界 | `core/ios/`, `features/ios/`, `features/overview/`, `app/window/mirror/` |
| `ios-airplay-server-architecture` | iOS AirPlay 实验性接收端与连接故障 | experimental | UxPlay/FairPlay 实验接入、VideoToolbox 首帧与重连、AudioQueue 持续静音恢复、后台启停和原子打包；真机音频已完成定向验收 | `core/airplay/`, `rust/device_bridge/src/airplay/` |
| `ios-airplay-video-playback` | AirPlay 视频媒体播放窗口 | experimental | 镜像/视频按类型开窗、首帧前镜像状态与失败重试、独立视频播放器；iPhone 6s 镜像实测通过，B 站视频无线投放待验收 | `core/airplay/`, `macos/Runner/`, `rust/device_bridge/` |
| `adb-dlna-video-receiver` | 视频 App 通过 DLNA 投到 macOS | experimental | SSDP 多网卡路由地址选择、UPnP 控制、AVPlayer 与 libmpv DASH 回退、播放窗口置顶、接收端名称热更新及真机验收边界 | `core/dlna/`, `features/dlna/`, `app/window/dlna/`, `macos/Runner/` |
| `adb-cast-receiver-dashboard` | AirPlay 与 DLNA 投屏接收统一入口 | active | 记录左侧投屏接收一级 Route、协议 Card 双列等高与名称区对齐、单列自然高度、启停与名称管理、状态复用及回归边界 | `app/router/`, `features/receivers/`, `features/overview/` |
| `ios-process-management` | iOS 进程表格与生命周期管理 | active | 全进程查询、应用归属筛选、图标缓存、3 秒轮询、未知性能指标、PID 身份回读及取消隔离 | `core/ios/`, `features/ios/` |
| `ios-apps-management` | iOS 应用筛选、收藏与图标管理 | active | Android 风格工具栏与表格、分类/拼音筛选、持久化收藏、字母索引、设备隔离、图标 helper 取消与验证边界 | `core/ios/`, `features/ios/`, `assets/ios/` |
| `ios-feature-parity` | iOS 布局、网页调试、录屏与 MCP 对齐 | active | WDA point 与截图像素换算、Safari Develop 入口、USB 原生录屏、MCP 平台路由和无真机回归边界 | `core/ios/`, `core/mcp/`, `features/screenshot/`, `features/ios/`, `macos/Runner/` |
| `adb-app-window-run-config-script` | App 子窗口 Run Configuration 生成脚本 | active | 记录 `script/generate_app_window_run_configs.sh` 如何生成模拟器管理窗口和控制台窗口的 IDE Flutter 运行入口 | `script/`, `.idea/runConfigurations/`, `app/window/` |
| `adb-macos-icon-assets` | macOS 图标资源机制 | active | 记录 Dock 图标、Flutter App logo、菜单栏 template icon 的资源边界和生成命令 | `assets/brand/`, `macos/Runner/Assets.xcassets/` |
| `adb-dashboard-device-identity` | Dashboard 设备身份入口 | active | 记录设备管理与模拟器列表同级入口、设备列表统计标签与自适应搜索筛选栏、设备行名称与 IP、品牌 Logo 圆角、左侧导航 App/设备身份切换、品牌优先与制造商兜底、概览缓存兼容、返回点击逻辑及 Material 绘制层级 | `features/overview/`, `features/devices/`, `core/device_info/` |
| `adb-device-context-menu` | 设备列表常用操作右键菜单 | active | 行高亮、截图保存及剪贴板、投屏与工具 Route、三平台能力区分、离线/删除与重复操作拦截及验证边界 | `features/devices/`, `features/control/`, `test/` |
| `adb-main-window-routing` | 主窗口层级路由 | active | 记录 Splash StartupGate、设备/模拟器/设置顶层 Route、设备工具 slug、应用详情嵌套路由及 Route 与 Riverpod 的职责边界 | `app/router/`, `features/overview/`, `features/apps/`, `features/devices/` |
| `adb-main-window-navigation` | 主窗口导航、帮助中心、底部控制台与系统版本 | active | AnyDeck 在线帮助入口与中英文文案、侧边栏底部控制台、可调高度日志面板、系统版本 Route、移除独立模拟器管理窗口和原生菜单入口、验证与人工边界 | `features/overview/`, `features/console/`, `app/window/`, `app/router/` |
| `adb-device-root-status` | Dashboard 手机 Root 状态标识 | active | 记录主页 Root 标识、检测链路、未知状态与控制 Tab 按钮移除 | `features/overview/`, `features/control/`, `core/providers/` |
| `adb-macos-signature-policy` | macOS 签名与 system policy 修复机制 | active | 记录 `FlutterMacOS.framework` 被 dyld system policy 拒绝加载时的签名、provenance/quarantine 排查与自动修复脚本 | `macos/`, `script/` |
| `adb-ai-mcp-server-architecture` | AI MCP 服务架构与集成机制 | active | 记录 AnyDeck 作为 AI MCP (Model Context Protocol) Server 的协议路由、Tools 注册、HTTP SSE 传输通道、SSE 停止时的连接回收、安全防御沙箱、默认收起且可展开的 Tools 清单、分类搜索同排布局与桌面管理控制台设计 | `core/mcp/`, `features/mcp/` |
| `adb-screenshot-layout-merge` | 截图录屏与布局分析合并机制 | active | 记录左侧入口收拢（Tab 8 归一化到 9）、顶部工具栏动态开关、底部缩放与图片信息栏、节点树与属性局部工具、三栏展开、共享画布坐标映射、原子化并发刷新、5 阶段录屏互斥机制与折叠屏截图自动选择 ON 内置物理屏 | `features/screenshot/`, `features/overview/`, `core/adb/` |
| `adb-connection-notifications-message-forwarding` | Android 连接通知与手机消息转发 | active | 记录 macOS UNUserNotificationCenter 原生通知与手机 App 图标附件、窗口聚焦、首次授权、DeviceDiscoveryTracker 单例守护、Android Companion NotificationListenerService 过滤与有界队列、ADB ContentProvider 轮询、SQLite 来源映射和增量刷新、多设备来源标签与名称快照、原始来源点击定位及切换隔离、Tab 15 消息列表 | `core/notifications/`, `features/messages/`, `tool/usage_companion/` |
| `adb-cross-channel-package-cache` | Wi-Fi 与 USB 双通道应用缓存共享机制 | active | 记录 Canonical Serial 规范序列号统一寻址、内存缓存同步直出、多通道 fallback 回退、本地图标目录复用以及 USB 刚插入时的通道就绪防抖与数据保护机制 | `core/apps/`, `core/providers/` |
| `adb-apps-batch-management` | 应用多选与批量管理机制 | active | 记录应用列表/网格多选状态维持、全选/反选/部分选联动、批量导出包、批量卸载、批量清除数据、批量冻结/解冻的工具栏交互、底层 ADB/HDC 命令机制与进度弹窗设计 | `features/apps/`, `core/apps/` |
| `adb-dashboard-header-bar-unification` | 仪表盘一级模块标题与页面样式统一机制 | active | 记录设备管理、模拟器管理、AI MCP、设置的顶部标题栏组件统一收口（DashboardHeaderBar）、72px 高度与 28px 内边距对齐、窗口拖拽、徽章规范及页面滚动布局一致性设计 | `features/widgets/`, `features/overview/`, `features/devices/`, `features/mcp/` |
| `hdc-harmony-feature-parity` | HarmonyOS 功能对齐与真机边界 | experimental | 性能 Tab、控制快捷操作的 HDC 实测，以及音频、摄像头、麦克风与跨应用消息的设备侧权限和工具链边界 | `core/harmony/`, `features/control/`, `features/performance/` |
| `huawei-share-core-integration` | Huawei Share 私有核心接入 | experimental | Debug/Release 自动打包与六成员严格制品校验、原子增量安装、发现端口共享与启动失败提示、真实就绪状态、私有制品固定版本与 SHA-256、默认 LAN 协商/有界回退、P2P入口收起与底层实现保留、2 秒来件确认兜底与真实 LAN 收件、DFile末块填充与短写边界修复、设置持久化/跨窗及 busy 门控、BLE 认证后切手机 WLAN/TCP 数据通道、匿名 stdin 凭据、Wi-Fi 恢复/定位与 Keychain 边界、恢复期 flock 互斥与精确 sibling helper 保留、1 GiB限制放开与数值溢出保护、固定高度发现舞台/紧凑头像/批次状态与扫描波纹、手机版本要求、连续批次队列与真实进度、记录/通知/目录设置及离线与真机验收边界 | `lib/core/nearby_share/`, `script/`, `macos/Runner.xcodeproj/` |
| `adb-workspace-prototype` | 小米 17 工作台交互原型 | experimental | 14 张本地原生截图、12 个工作台入口、应用详情十类标签、原型结构、模拟边界与验证记录 | `prototype/interactive/` |

## 新增知识库规则

产品体验修复记录：[AnyDeck 产品体验问题修复](adb-product-review-fixes.md)，按 AD 编号记录实现、测试和未验收范围；AD-010 同时记录设备列表备注列隐藏与备注功能保留。

每次新增的需求或重大功能迭代，在开发完成后均必须将其技术设计、关键实现与命令机制以知识文档的形式沉淀在 `agent/knowledge/` 目录下，并在此索引中进行登记。
