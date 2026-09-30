/// AdbManage 核心全局 Riverpod Provider 统一聚合导出入口（Barrel File）。
///
/// 为了满足代码架构规范（单个类和文件不超过 500 行），所有 Provider 均已按照职责领域拆分至
/// [modules/] 子目录下进行高内聚、低耦合的模块化维护：
///
/// 1. [modules/service_providers.dart]
///    底层 ADB / HDC / Scrcpy / WebDebug 等核心基础设施服务单例 Provider。
///
/// 2. [modules/device_tracking_providers.dart]
///    设备自适应心跳轮询、常驻 track-devices 守护监听与在线状态快速响应 Provider。
///
/// 3. [modules/package_providers.dart]
///    已安装应用列表、持久化跨通道秒开缓存、分批图标加载与单包增量更新 Provider。
///
/// 4. [modules/device_overview_providers.dart]
///    软硬件参数概览信息流、Root 提权安全检测与离线概览缓存 Provider。
///
/// 5. [modules/file_providers.dart]
///    远程文件列表、前进/后退/向上导航状态、路径切换与过滤搜索 Provider。
///
/// 6. [modules/dashboard_state_providers.dart]
///    主工作区 Tab 索引、当前选中设备/应用、Logcat 控制器及 Scrcpy 投屏会话跟踪 Provider。
///
/// 7. [modules/emulator_terminal_providers.dart]
///    AVD 模拟器冷启动与运行状态映射、终端命令调试会话 Provider。
///
/// 8. [modules/screen_power_providers.dart]
///    物理手机息屏控制、自动亮度恢复与 getevent 物理触摸唤醒防锁死机制 Provider。
///
/// 9. [modules/registered_device_model.dart]
///    设备注册表统一数据模型 [RegisteredDevice] 及 SDK/系统版本查询 Provider。
///
/// 10. [modules/device_registry_storage.dart]
///     注册表本地持久化、历史脏数据迁移与缓存解析服务。
///
/// 11. [modules/device_registry_merger.dart]
///     多通道归一与“在线优先、USB 优先”最佳代表选举服务。
///
/// 12. [modules/device_registry_probe_service.dart]
///     硬件序列号、局域网 IP 与真实型号非阻塞探查服务。
///
/// 13. [modules/device_registry_actions.dart]
///     局域网同一网段测试、Ping 诊断、TCP/IP 无线连接与配对操作。
///
/// 14. [modules/device_registry_providers.dart]
///     全局设备注册表状态控制器 [DeviceRegistryNotifier] 与 [deviceRegistryProvider]。
library;

export 'modules/dashboard_state_providers.dart';
export 'modules/device_overview_providers.dart';
export 'modules/device_registry_actions.dart';
export 'modules/device_registry_merger.dart';
export 'modules/device_registry_probe_service.dart';
export 'modules/device_registry_providers.dart';
export 'modules/device_registry_storage.dart';
export 'modules/device_tracking_providers.dart';
export 'modules/emulator_terminal_providers.dart';
export 'modules/file_providers.dart';
export 'modules/package_providers.dart';
export 'modules/registered_device_model.dart';
export 'modules/screen_power_providers.dart';
export 'modules/service_providers.dart';
export 'modules/wireless_connection_provider.dart';
