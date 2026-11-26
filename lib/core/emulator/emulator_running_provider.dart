import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/modules/device_tracking_providers.dart';
import 'emulator_connection.dart';
import 'harmony/harmony_emulator_probes.dart';
import 'ios/ios_simulator_providers.dart';

/// 各平台正在运行的模拟器实例数。
typedef RunningEmulatorCounts = ({int android, int harmony, int ios});

/// 没有运行实例时各平台的数量。
const RunningEmulatorCounts noRunningEmulators = (
  android: 0,
  harmony: 0,
  ios: 0,
);

/// 按平台汇总运行实例，数量相同时侧栏无需重建。
final runningEmulatorCountsProvider =
    Provider.autoDispose<RunningEmulatorCounts>((ref) {
      final ios = ref.watch(
        iosRunningSimulatorCountProvider.select(
          (snapshot) => snapshot.value ?? 0,
        ),
      );
      final devices = ref.watch(discoveredDevicesProvider).value ?? [];
      final harmonyProbes = ref.watch(harmonyEmulatorProbesProvider);
      final android = <String>{};
      final harmony = <String>{};
      for (final device in devices) {
        if (device.isIos || (device.isHarmony && !device.isOnline)) continue;
        if (EmulatorConnectionService.isTransport(device.id)) {
          // ADB 未授权或离线时，transport 仍表明 Android 模拟器已启动。
          (device.isHarmony ? harmony : android).add(device.id);
        } else if (device.isHarmony && harmonyProbes[device.id] == true) {
          harmony.add(device.id);
        }
      }
      return (android: android.length, harmony: harmony.length, ios: ios);
    });
