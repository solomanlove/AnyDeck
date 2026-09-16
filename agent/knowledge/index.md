# Knowledge Index (AI 需求与知识库索引)

本索引用于管理 AdbManage 项目内已实现的需求与业务机制知识库 (Knowledge)。所有的 AI 助手在进行二次开发或优化相关需求前，应根据本索引的指引，优先调取对应模块的知识库文档。

## 知识库列表

### 1. 业务与机制知识 (Business & Mechanisms)

| Knowledge | 中文名 | 状态 | 用途 | 关联模块 |
| --- | --- | --- | --- | --- |
| `adb-local-apk-inspector` | macOS 本地 APK 详情与安装 | active | Finder 文件关联、独立窗口、Rust 离线解析、签名信息与主窗口安装队列、缓存刷新及回归边界 | `core/apk/`, `features/apk/`, `app/window/apk/`, `rust/apk_inspector/` |
| `adb-terminal-pty` | 终端 PTY 与 root 提示符 | active | 记录真实 shell 回显、su 提权显示、目录变化、流式换行处理与回归边界 | `core/terminal/`, `features/terminal/` |
| `adb-app-permissions` | 应用权限分类与批量撤销 | active | 记录动态 / 静态 / 未知权限分类、当前用户隔离、批量撤销与回读结果、共享面板及回归验证 | `core/apps/`, `features/apps/` |
| `adb-usage-companion` | 手机使用统计、位置记录与 ADB 历史同步 | active | 可见授权、系统统计口径、位置前台服务、手机离线库、分页游标与 SQLite 事务、内嵌地图底图、图标复用及验证边界 | `core/usage/`, `features/apps/`, `tool/usage_companion/` |
| `adb-device-rust-sessions` | 屏幕投屏、摄像头、麦克风与手机剪贴板 Rust 底座 | active | 彻底移除 C++ 插件，屏幕投屏、VideoToolbox 硬解、AudioQueue、触控注入、摄像头、麦克风、剪贴板全面由纯 Rust 底座承接 | `core/scrcpy/`, `features/apps/`, `rust/device_bridge/` |
| `adb-device-rust-sessions-test` | Rust 设备会话回归验证 | active | 自动验证结果、平台门槛、生成视频帧解码与真机回归清单 | `test/`, `rust/device_bridge/` |
| `adb-embedded-camera` | 内嵌摄像头预览 | active | scrcpy camera 参数、独立会话/端口、原生 Texture 复用、手动启停及销毁回收、macOS 限制与回归边界 | `core/scrcpy/`, `features/apps/`, `rust/device_bridge/` |
| `adb-cert-management` | 证书管理机制 | active | 记录用户证书与系统证书（Root 权限，包含 Android 10+ 内存挂载与 Conscrypt APEX 挂载）的导入机制与 adb 命令设计 | `control/` (控制面板) |
| `adb-desktop-window-shortcuts` | 桌面独立窗口快捷键机制 | active | 记录控制台窗口、模拟器管理窗口等独立子窗口的本地快捷键关闭策略与职责边界 | `app/window/` (桌面多窗口) |
| `adb-tabs-features-principles` | 各 Tab 功能与实现原理指南 | active | 梳理概览的平台字段分流、内存占用与容量卡布局，以及控制、应用（含 DEBUG 标识保留与缓存恢复）、文件预览、日志、终端、进程右键复制与停止、网页调试、布局分析、性能监控、网络/端口转发等 Tab 的功能设计与底层原理 | `dashboard/` (主面板各 Tab) |
| `adb-wifi-connection-principles` | ADB 无线调试连接与断开原理 | active | 记录手动连接弹窗内置四步指南与排障、无线调试底层 TCP/IP 监听模式切换、多级 IP 地址自动探测机制（`ip route`/`ip addr`）、合并去重架构与连接操作链路设计 | `dashboard/devices/` (设备控制行) |
| `devices_manager` | 设备唯一标识判断机制 | active | 记录 AdbDevice.id 命令路由、HDC 在线状态过滤、ADB/HDC 同地址优先级，以及根据 hardware serial 进行多连接合并与物理去重 | `dashboard/devices/` (设备控制行) |
| `adb-mirror-window-launcher-script` | 投屏子窗口启动文件生成脚本 | active | 记录 `script/generate_mirror_window_launcher.sh` 如何复用 `multi_window <windowId> <json>` 参数生成可执行启动文件 | `script/`, `app/window/mirror/` |
| `adb-mirror-window-behavior` | 投屏独立窗口行为机制 | active | 记录投屏窗口设备名称优先级、比例适配、横竖屏无断流渲染、设备信息悬浮层、单 App 工具栏规则，以及 HarmonyOS HDC 控制映射 | `app/window/mirror/`, `rust/device_bridge/`, `core/harmony/` |
| `ios-mirror-principles` | iOS 投屏与设备管理机制 | active | 记录 go-ios 集成、USB 投屏原理（MJPEG 字节流解析）、多窗口 Isolate 隔离下的状态同步与测试桩设计 | `core/ios/`, `app/window/mirror/` |
| `adb-app-window-run-config-script` | App 子窗口 Run Configuration 生成脚本 | active | 记录 `script/generate_app_window_run_configs.sh` 如何生成模拟器管理窗口和控制台窗口的 IDE Flutter 运行入口 | `script/`, `.idea/runConfigurations/`, `app/window/` |
| `adb-macos-icon-assets` | macOS 图标资源机制 | active | 记录 Dock 图标、Flutter App logo、菜单栏 template icon 的资源边界和生成命令 | `assets/brand/`, `macos/Runner/Assets.xcassets/` |
| `adb-dashboard-device-identity` | Dashboard 设备身份入口 | active | 记录左侧导航顶部 App/设备身份切换、品牌优先与制造商图标兜底、概览缓存兼容、返回设备管理点击逻辑、workspace 顶部布局边界及玻璃背景内的 Material 绘制层级 | `features/overview/`, `features/devices/`, `core/device_info/` |
| `adb-macos-signature-policy` | macOS 签名与 system policy 修复机制 | active | 记录 `FlutterMacOS.framework` 被 dyld system policy 拒绝加载时的签名、provenance/quarantine 排查与自动修复脚本 | `macos/`, `script/` |
| `adb-ai-mcp-server-architecture` | AI MCP 服务架构与集成机制 | active | 记录 AnyDeck 作为 AI MCP (Model Context Protocol) Server 的协议路由、Tools 注册、SSE/Stdio 双通道传输、SSE 停止时的连接回收、安全防御沙箱与桌面管理控制台设计 | `core/mcp/`, `features/mcp/` |
| `adb-screenshot-layout-merge` | 截图录屏与布局分析合并机制 | active | 记录左侧入口收拢（Tab 8 归一化到 9）、顶部工具栏动态开关、三栏展开、共享画布坐标映射、原子化并发刷新与 5 阶段录屏互斥机制 | `features/screenshot/`, `features/overview/` |
| `adb-connection-notifications-message-forwarding` | Android 连接通知与手机消息转发 | active | 记录 macOS UNUserNotificationCenter 原生通知与窗口聚焦、首次授权、AdbDeviceTracker 单例守护、Android Companion NotificationListenerService 过滤与有界队列、ADB ContentProvider 轮询、SQLite 来源映射和增量刷新、Tab 15 消息列表 | `core/notifications/`, `features/messages/`, `tool/usage_companion/` |
| `adb-cross-channel-package-cache` | Wi-Fi 与 USB 双通道应用缓存共享机制 | active | 记录 Canonical Serial 规范序列号统一寻址、内存缓存同步直出、多通道 fallback 回退、本地图标目录复用以及 USB 刚插入时的通道就绪防抖与数据保护机制 | `core/apps/`, `core/providers/` |

## 新增知识库规则
每次新增的需求或重大功能迭代，在开发完成后均必须将其技术设计、关键实现与命令机制以知识文档的形式沉淀在 `agent/knowledge/` 目录下，并在此索引中进行登记。
