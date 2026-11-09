import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../harmony/harmony_mirror_service.dart';
import '../../ios/ios_mirror_service.dart';
import '../../scrcpy/embedded_scrcpy_service.dart';
import '../../adb/discovered_device.dart';
import '../../adb/device_discovery_tracker.dart';
import '../../adb/device_polling_controller.dart';
import 'dashboard_state_providers.dart';
import 'service_providers.dart';

/// 自适应轮询控制器 Provider。
///
/// 负责在主窗口处于设备列表页面时周期性轮询 ADB/iOS 设备状态；在子窗口或非设备管理页面时智能休眠以降低 CPU 占用。
final devicePollingControllerProvider =
    Provider.autoDispose<DevicePollingController>((ref) {
      final adbService = ref.watch(adbServiceProvider);
      final iosDeviceService = ref.watch(iosDeviceServiceProvider);
      final isSub = ref.watch(windowIdProvider).isNotEmpty;

      // 主窗口下，当没有选择设备或正处于设备管理Tab(-1)，且未展示设置页面时（即处于设备管理列表“主页”），才应该运行轮询
      final selectedDevice = ref.watch(selectedDeviceProvider);
      final selectedTool = ref.watch(selectedToolTabProvider);
      final isDeviceListVisible =
          !isSub && (selectedDevice == null || selectedTool == -1) && selectedTool != 12;

      final controller = DevicePollingController(
        adbService: adbService,
        iosDeviceService: iosDeviceService,
        isSubWindow: isSub,
        isDeviceListVisible: isDeviceListVisible,
      );
      ref.onDispose(() => controller.dispose());
      return controller;
    });

/// 主窗口常驻的跨平台设备发现 Provider。
///
/// 聚合 ADB 事件流、HDC/iOS 自动检测及主动刷新结果，退出应用时释放资源。
final deviceDiscoveryTrackerProvider = Provider<DeviceDiscoveryTracker>((ref) {
  final adbService = ref.watch(adbServiceProvider);
  final iosService = ref.watch(iosDeviceServiceProvider);
  final hdcService = ref.watch(hdcServiceProvider);
  final isSub = ref.watch(windowIdProvider).isNotEmpty;

  final tracker = DeviceDiscoveryTracker(
    adbService: adbService,
    iosDeviceService: iosService,
    hdcService: hdcService,
    isSubWindow: isSub,
  );

  ref.onDispose(tracker.dispose);
  return tracker;
});

/// ADB、HDC 与 iOS 的设备发现列表，包含在线、offline 或 unauthorized 等记录。
///
/// 主窗口订阅发现聚合流；子窗口使用独立控制器流，但不启动轮询。
final discoveredDevicesProvider = StreamProvider.autoDispose<List<DiscoveredDevice>>((ref) {
  final isSub = ref.watch(windowIdProvider).isNotEmpty;
  if (isSub) {
    final controller = ref.watch(devicePollingControllerProvider);
    return controller.deviceStream;
  }
  final tracker = ref.watch(deviceDiscoveryTrackerProvider);
  return tracker.deviceStream;
});

/// 用于响应式监听指定设备是否在线的 Provider。
///
/// 入参 [deviceId] 为设备 ID。子窗口下通过判断是否包含活跃的投屏 Session 回退判断。
final deviceOnlineProvider = Provider.autoDispose.family<bool, String>((
  ref,
  deviceId,
) {
  final isSub = ref.watch(windowIdProvider).isNotEmpty;
  if (isSub) {
    // 子 Isolate 下轮询轮询被禁用，通过是否包含激活的投屏 Session 来判断在线状态
    return ref.watch(activeIosMirrorProvider(deviceId)) != null ||
        ref.watch(activeHarmonyMirrorProvider(deviceId)) != null ||
        ref.watch(activeEmbeddedMirrorProvider(deviceId)) != null;
  }
  final activeDevicesAsync = ref.watch(discoveredDevicesProvider);
  final activeDevices = activeDevicesAsync.value ?? [];
  return activeDevices.any((d) => d.id == deviceId && d.isOnline);
});
