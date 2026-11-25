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

/// 汇总三平台状态，侧栏只在是否有模拟器运行发生变化时重建。
final anyEmulatorRunningProvider = Provider.autoDispose<bool>((ref) {
  final iosRunning = ref.watch(
    iosSimulatorRunningProvider.select((snapshot) => snapshot.value ?? false),
  );
  final devices = ref.watch(discoveredDevicesProvider).value ?? [];
  var running = iosRunning;
  for (final device in devices) {
    if (device.isIos || (device.isHarmony && !device.isOnline)) continue;
    if (EmulatorConnectionService.isTransport(device.id)) {
      // ADB 未授权或离线时，transport 仍表明 Android 模拟器已启动。
      running = true;
    } else if (device.isHarmony && _localHdcAddress.hasMatch(device.id)) {
      final devEcoRunning = ref.watch(_devEcoTargetProvider(device.id));
      running = running || devEcoRunning.value == true;
    }
  }
  return running;
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
