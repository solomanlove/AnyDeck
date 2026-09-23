import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../harmony/harmony_mirror_service.dart';
import '../../ios/ios_mirror_service.dart';
import '../../scrcpy/embedded_scrcpy_service.dart';
import '../../adb/adb_device.dart';
import '../../adb/adb_device_tracker.dart';
import '../../adb/adb_heartbeat_controller.dart';
import 'dashboard_state_providers.dart';
import 'service_providers.dart';

/// 自适应心跳控制器 Provider。
///
/// 负责在主窗口处于设备列表页面时周期性轮询 ADB/HDC/iOS 设备状态；在子窗口或非设备管理页面时智能休眠以降低 CPU 占用。
final adbHeartbeatControllerProvider =
    Provider.autoDispose<AdbHeartbeatController>((ref) {
      final adbService = ref.watch(adbServiceProvider);
      final iosDeviceService = ref.watch(iosDeviceServiceProvider);
      final hdcService = ref.watch(hdcServiceProvider);
      final isSub = ref.watch(windowIdProvider).isNotEmpty;

      // 主窗口下，当没有选择设备或正处于设备管理Tab(-1)，且未展示设置页面时（即处于设备管理列表“主页”），才应该运行心跳
      final selectedDevice = ref.watch(selectedDeviceProvider);
      final selectedTool = ref.watch(selectedToolTabProvider);
      final isDeviceListVisible =
          !isSub && (selectedDevice == null || selectedTool == -1) && selectedTool != 12;

      final controller = AdbHeartbeatController(
        adbService: adbService,
        iosDeviceService: iosDeviceService,
        hdcService: hdcService,
        isSubWindow: isSub,
        isDeviceListVisible: isDeviceListVisible,
      );
      ref.onDispose(() => controller.dispose());
      return controller;
    });

/// 主窗口常驻 ADB 设备监听进程 Provider。
///
/// 采用单一长驻 `adb track-devices` 守护进程，应用生命周期内常驻，退出应用时释放。
final adbDeviceTrackerProvider = Provider<AdbDeviceTracker>((ref) {
  final adbService = ref.watch(adbServiceProvider);
  final iosService = ref.watch(iosDeviceServiceProvider);
  final hdcService = ref.watch(hdcServiceProvider);
  final isSub = ref.watch(windowIdProvider).isNotEmpty;

  final tracker = AdbDeviceTracker(
    adbService: adbService,
    iosDeviceService: iosService,
    hdcService: hdcService,
    isSubWindow: isSub,
  );

  ref.onDispose(tracker.dispose);
  return tracker;
});

/// 自动轮询/监听的实时 ADB 设备列表 StreamProvider。
///
/// 主窗口接入常驻 `track-devices` 流，子窗口则安全回退到心跳流以保证 Isolate 独立稳定。
final devicesProvider = StreamProvider.autoDispose<List<AdbDevice>>((ref) {
  final isSub = ref.watch(windowIdProvider).isNotEmpty;
  if (isSub) {
    final controller = ref.watch(adbHeartbeatControllerProvider);
    return controller.deviceStream;
  }
  final tracker = ref.watch(adbDeviceTrackerProvider);
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
    // 子 Isolate 下心跳轮询被禁用，通过是否包含激活的投屏 Session 来判断在线状态
    return ref.watch(activeIosMirrorProvider(deviceId)) != null ||
        ref.watch(activeHarmonyMirrorProvider(deviceId)) != null ||
        ref.watch(activeEmbeddedMirrorProvider(deviceId)) != null;
  }
  final activeDevicesAsync = ref.watch(devicesProvider);
  final activeDevices = activeDevicesAsync.value ?? [];
  return activeDevices.any((d) => d.id == deviceId && d.isOnline);
});
