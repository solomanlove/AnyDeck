import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../scrcpy/mirror_transport_devices_provider.dart';
import 'device_tracking_providers.dart';

/// Android 概览依赖真实 ADB 在线状态，投屏降档时的空 Texture 不等于设备离线。
/// 主窗口保留原设备发现路径；子窗口复用选路 Tracker，不新增轮询或监听进程。
final androidOverviewOnlineProvider = Provider.autoDispose.family<bool, String>(
  (ref, deviceId) {
    if (ref.watch(windowIdProvider).isEmpty) {
      return ref.watch(deviceOnlineProvider(deviceId));
    }
    // 初始快照尚未到达时暂停硬件查询；仅目标设备在线值改变才刷新概览。
    return ref.watch(
      mirrorTransportDevicesProvider.select(
        (devices) =>
            devices.value?.any(
              (device) => device.id == deviceId && device.isOnline,
            ) ??
            false,
      ),
    );
  },
);
