import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../logging/log_service.dart';
import '../../adb/adb_service.dart';
import '../../apps/app_data_backup_service.dart';
import '../../apps/app_management_service.dart';
import '../../apps/app_permission_service.dart';
import '../../cache/cache_cleanup_service.dart';
import '../../device_actions/device_action_service.dart';
import '../../device_actions/foreground_app_service.dart';
import '../../device_info/device_info_service.dart';
import '../../files/file_manager_service.dart';
import '../../harmony/harmony_mirror_service.dart';
import '../../harmony/hdc_service.dart';
import '../../layout_inspector/layout_inspector_service.dart';
import '../../process/host_platform_service.dart';
import '../../process/process_service.dart';
import '../../scrcpy/scrcpy_service.dart';
import '../../web_debug/web_debug_service.dart';
import '../../web_debug/webpage_target.dart';
import 'device_registry_providers.dart';
import 'registered_device_model.dart';

export '../../cron/cron_scheduler_service.dart';
export '../../ios/ios_ble_mouse_service.dart';
export '../../ios/ios_wda_client.dart';

/// 所有命令型 Provider 共享的全局 ADB 服务单例实例。
///
/// 内部将命令与执行日志回流至 [logHistoryProvider]，方便在日志面板中追踪排查。
final adbServiceProvider = Provider<AdbService>((ref) {
  return AdbService(
    onLog: (message, {tag = 'adb', level = 'I'}) {
      ref
          .read(logHistoryProvider.notifier)
          .log(message, tag: tag, level: level);
    },
  );
});

/// 所有命令型 Provider 共享的全局 HDC（鸿蒙）服务单例实例。
///
/// 内部将 HDC 命令执行日志回流至 [logHistoryProvider]。
final hdcServiceProvider = Provider<HdcService>((ref) {
  return HdcService(
    onLog: (message, {tag = 'hdc', level = 'I'}) {
      ref
          .read(logHistoryProvider.notifier)
          .log(message, tag: tag, level: level);
    },
  );
});

/// 鸿蒙镜像（投屏）管理服务单例 Provider。
///
/// 在 Provider 销毁时会自动停止并回收所有活跃投屏会话。
final harmonyMirrorServiceProvider = Provider<HarmonyMirrorService>((ref) {
  final hdcService = ref.watch(hdcServiceProvider);
  final service = HarmonyMirrorService(hdcService);
  ref.onDispose(service.stopAll);
  return service;
});

/// 设备操作门面 Provider，负责按键注入、屏幕控制、设置开关和底层 shell 读取。
///
/// 支持根据 [deviceId] 自动判定并分发至 Android（ADB）或鸿蒙（HDC）环境。
final deviceActionServiceProvider = Provider<DeviceActionService>((ref) {
  return DeviceActionService(
    ref.watch(adbServiceProvider),
    hdc: ref.watch(hdcServiceProvider),
    sdkVersionResolver: (deviceId) =>
        ref.read(deviceSdkVersionProvider(deviceId)),
    isHarmonyResolver: (deviceId) {
      if (deviceId.startsWith('harmony:')) return true;
      if (ref.read(harmonyMirrorServiceProvider).isActive(deviceId)) return true;
      final registered = ref.read(deviceRegistryProvider);
      return registered.any((d) => d.id == deviceId && d.isHarmony);
    },
  );
});

/// 前台应用识别门面 Provider，负责投屏窗口长按返回键的应用判断与强行停止。
final foregroundAppServiceProvider = Provider<ForegroundAppService>((ref) {
  return ForegroundAppService(ref.watch(adbServiceProvider));
});

/// 应用管理门面 Provider，负责安装、卸载、启动、清理应用以及获取已安装列表。
final appManagementServiceProvider = Provider<AppManagementService>((ref) {
  return AppManagementService(
    ref.watch(adbServiceProvider),
    hdc: ref.watch(hdcServiceProvider),
  );
});

/// 应用数据备份门面 Provider，负责按系统版本选择 adb backup、run-as 或 Root tar 备份还原机制。
final appDataBackupServiceProvider = Provider<AppDataBackupService>((ref) {
  return AppDataBackupService(ref.watch(adbServiceProvider));
});

/// 应用权限管理门面 Provider，负责查询、授予和撤销应用权限（如危险权限、特殊权限等）。
final appPermissionServiceProvider = Provider<AppPermissionService>((ref) {
  return AppPermissionService(ref.watch(adbServiceProvider));
});

/// 远程文件管理门面 Provider，负责针对 Android/鸿蒙设备的 push、pull、删除和目录遍历。
final fileManagerServiceProvider = Provider<FileManagerService>((ref) {
  return FileManagerService(
    ref.watch(adbServiceProvider),
    hdc: ref.watch(hdcServiceProvider),
    isHarmonyResolver: (deviceId) {
      final registered = ref.read(deviceRegistryProvider);
      return registered.any((d) => d.id == deviceId && d.isHarmony);
    },
  );
});

/// 设备信息查询服务 Provider，提供只读的硬件参数与系统信息概览抓取。
final deviceInfoServiceProvider = Provider<DeviceInfoService>((ref) {
  return DeviceInfoService(ref.watch(adbServiceProvider));
});

/// 布局分析服务 Provider，负责抓取 `uiautomator` 结构 XML 和屏幕截图。
final layoutInspectorServiceProvider = Provider<LayoutInspectorService>((ref) {
  return LayoutInspectorService(ref.watch(adbServiceProvider));
});

/// Scrcpy 进程管理器 Provider。Provider 销毁时会停止并回收所有活跃会话。
final scrcpyServiceProvider = Provider<ScrcpyService>((ref) {
  final service = ScrcpyService();
  ref.onDispose(service.stopAll);
  return service;
});

/// 系统进程管理门面 Provider，负责查询运行中进程列表及结束指定进程。
final processServiceProvider = Provider<ProcessService>((ref) {
  return ProcessService(ref.watch(adbServiceProvider), ref.watch(hdcServiceProvider));
});

/// 宿主机系统平台服务 Provider，负责与当前运行的桌面宿主机 OS（如 macOS / Windows / Linux）交互。
final hostPlatformServiceProvider = Provider<HostPlatformService>((ref) {
  return HostPlatformService();
});

/// 本机缓存清理服务 Provider，只处理 AnyDeck 自身的缓存目录（如临时截屏、图标等）。
final cacheCleanupServiceProvider = Provider<CacheCleanupService>((ref) {
  return CacheCleanupService();
});

/// 单台设备当前运行进程列表 Provider。
///
/// 入参 [deviceId] 为目标设备 ID，自动在离开相关页面时释放回收。
final processesProvider = FutureProvider.autoDispose
    .family<List<AdbProcess>, String>((ref, deviceId) {
      final registry = ref.watch(deviceRegistryProvider);
      final isHarmony = registry.any((d) => d.id == deviceId && d.isHarmony);
      return ref
          .watch(processServiceProvider)
          .getProcesses(deviceId, isHarmony: isHarmony);
    });

/// 网页调试服务 Provider，负责端口转发与 Chrome DevTools 协议目标发现。
final webDebugServiceProvider = Provider<WebDebugService>((ref) {
  final service = WebDebugService(
    ref.watch(adbServiceProvider),
    hdc: ref.watch(hdcServiceProvider),
  );
  ref.onDispose(service.disposeAll);
  return service;
});

/// 单台设备的运行网页调试目标列表 Provider。
///
/// 入参 [deviceId] 为目标设备 ID，结合 [showAllWebTargetsProvider] 决定是否展示全部目标。
final webTargetsProvider = FutureProvider.autoDispose
    .family<List<WebpageTarget>, String>((ref, deviceId) async {
      final service = ref.watch(webDebugServiceProvider);
      final showAllTargets = ref.watch(showAllWebTargetsProvider);
      final isHarmony = ref
          .read(deviceRegistryProvider)
          .any((d) => d.id == deviceId && d.isHarmony);
      await Future<void>.delayed(Duration.zero);
      return service.scanTargets(
        deviceId,
        includeAllTargets: showAllTargets,
        isHarmony: isHarmony,
      );
    });

/// 当前选中的网页调试目标 Provider。
final selectedWebTargetProvider =
    NotifierProvider<SelectedWebTargetNotifier, WebpageTarget?>(
      SelectedWebTargetNotifier.new,
    );

/// 网页调试目标选择状态控制器。
class SelectedWebTargetNotifier extends Notifier<WebpageTarget?> {
  @override
  WebpageTarget? build() => null;

  @override
  set state(WebpageTarget? value) => super.state = value;
}

/// 是否显示 Stetho、WebView 等全部 DevTools 调试目标的开关 Provider。
final showAllWebTargetsProvider =
    NotifierProvider<ShowAllWebTargetsNotifier, bool>(
      ShowAllWebTargetsNotifier.new,
    );

/// 网页调试目标展示范围状态控制器，内部持久化到 SharedPreferences。
class ShowAllWebTargetsNotifier extends Notifier<bool> {
  static const _key = 'web_debug.show_all_targets';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  /// 切换显示/隐藏全部目标
  Future<void> toggle() async {
    final next = !state;
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, next);
  }
}
