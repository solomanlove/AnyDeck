import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings/app_settings_controller.dart';
import '../adb/adb_device.dart';
import '../adb/adb_device_tracker.dart';
import '../providers/app_providers.dart';

/// 投屏选路专用的事件快照：主窗口复用 tracker，子 Isolate 共享一个仅 ADB 的监听。
/// 不启用子窗口心跳或 iOS/HDC 轮询，最后一个订阅释放时回收 track-devices 进程。
final mirrorTransportDevicesProvider =
    StreamProvider.autoDispose<List<AdbDevice>>((ref) {
      final isSubWindow = ref.watch(windowIdProvider).isNotEmpty;
      final tracker = isSubWindow
          ? AdbDeviceTracker(adbService: ref.watch(adbServiceProvider))
          : ref.watch(adbDeviceTrackerProvider);
      if (isSubWindow) ref.onDispose(tracker.dispose);
      return Stream<List<AdbDevice>>.multi((controller) {
        final subscription = tracker.deviceStream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.add(tracker.currentDevices);
        controller.onCancel = subscription.cancel;
      });
    });
