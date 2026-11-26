import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/modules/device_tracking_providers.dart';
import '../../providers/modules/service_providers.dart';

final _localHdcAddress = RegExp(r'^(?:127\.0\.0\.1|\[::1\]):\d+$');
final _devEcoName = RegExp(
  r'^ohos\.qemu\.hvd\.name[ \t]*=[ \t]*\S',
  multiLine: true,
);

/// 设备管理与侧栏共用现代 DevEco 的探测结果。null 表示尚未确认。
final harmonyEmulatorProbesProvider = Provider.autoDispose<Map<String, bool?>>((
  ref,
) {
  final devices = ref.watch(discoveredDevicesProvider).value ?? [];
  return {
    for (final device in devices)
      if (device.isHarmony &&
          device.isOnline &&
          _localHdcAddress.hasMatch(device.id))
        device.id: ref.watch(_devEcoTargetProvider(device.id)).value,
  };
});

/// 同一个连续连接只查询一次；回环地址本身也可能是转发的真机。
final _devEcoTargetProvider = FutureProvider.autoDispose.family<bool?, String>((
  ref,
  id,
) async {
  final result = await ref.watch(hdcServiceProvider).run([
    '-t',
    id,
    'shell',
    'param get | grep hvd',
  ], timeout: const Duration(seconds: 3));
  if (result.isSuccess) return _devEcoName.hasMatch(result.stdout);
  // grep 未匹配时可能返回 1；HDC 通信错误由服务转入 stderr。
  if (result.exitCode == 1 &&
      result.stdout.trim().isEmpty &&
      result.stderr.trim().isEmpty) {
    return false;
  }
  return null;
});
