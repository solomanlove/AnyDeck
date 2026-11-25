import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/modules/device_tracking_providers.dart';
import '../providers/modules/service_providers.dart';
import 'emulator_connection.dart';
import 'ios/ios_simulator_providers.dart';

final _localHdcAddress = RegExp(r'^(?:127\.0\.0\.1|\[::1\]):\d+$');
final _devEcoName = RegExp(
  r'^ohos\.qemu\.hvd\.name[ \t]*=[ \t]*\S',
  multiLine: true,
);

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
      final android = <String>{};
      final harmony = <String>{};
      for (final device in devices) {
        if (device.isIos || (device.isHarmony && !device.isOnline)) continue;
        if (EmulatorConnectionService.isTransport(device.id)) {
          // ADB 未授权或离线时，transport 仍表明 Android 模拟器已启动。
          (device.isHarmony ? harmony : android).add(device.id);
        } else if (device.isHarmony && _localHdcAddress.hasMatch(device.id)) {
          if (ref.watch(_devEcoTargetProvider(device.id)).value == true) {
            harmony.add(device.id);
          }
        }
      }
      return (android: android.length, harmony: harmony.length, ios: ios);
    });

/// 现代 DevEco 使用回环地址。确认模拟器属性，避免把本地转发的真机算进去。
/// 同一个连续连接复用查询结果，连接离开设备发现列表后自动回收。
final _devEcoTargetProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  id,
) async {
  final result = await ref.watch(hdcServiceProvider).run([
    '-t',
    id,
    'shell',
    'param get | grep hvd',
  ], timeout: const Duration(seconds: 3));
  return result.isSuccess && _devEcoName.hasMatch(result.stdout);
});
