import '../adb/adb_device.dart';
import '../adb/adb_result.dart';
import '../adb/adb_service.dart';

/// AVD 与 ADB transport 的关联；console 查询不依赖 Android shell 授权。
class EmulatorConnectionService {
  const EmulatorConnectionService(this.adb);

  final AdbService adb;

  Future<Map<String, AdbDevice>> inspect(List<AdbDevice> devices) async {
    final result = <String, AdbDevice>{};
    for (final device in devices) {
      if (!RegExp(r'^emulator-\d+$').hasMatch(device.id)) continue;
      final response = await adb.run([
        '-s',
        device.id,
        'emu',
        'avd',
        'name',
      ], timeout: const Duration(seconds: 3));
      var name = response.isSuccess ? parseAvdName(response.stdout) : null;
      if (name == null && device.isOnline) {
        for (final property in [
          'ro.boot.qemu.avd_name',
          'ro.kernel.qemu.avd_name',
        ]) {
          final value = await adb.shellArgs(device.id, ['getprop', property]);
          if (value.isSuccess && value.stdout.trim().isNotEmpty) {
            name = value.stdout.trim();
            break;
          }
        }
      }
      if (name != null) result[name] = device;
    }
    return result;
  }

  /// console 回复仅接受单个 AVD 名称，过滤 OK、欢迎信息及失败描述。
  static String? parseAvdName(String output) {
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where(
          (line) =>
              line.isNotEmpty &&
              line != 'OK' &&
              !line.startsWith('Android Console:'),
        );
    final names = lines
        .where((line) => RegExp(r'^[\w.\-]+$').hasMatch(line))
        .toList();
    return names.length == 1 ? names.single : null;
  }

  /// 仅重置所选模拟器的 transport，不重启全局 server、不删除授权密钥。
  Future<AdbResult> reconnect(String deviceId) {
    _validate(deviceId);
    return adb.run(['-s', deviceId, 'reconnect']);
  }

  /// console 关闭允许正常退出并保存状态，未授权设备也无需 shell。
  Future<AdbResult> stop(String deviceId) {
    _validate(deviceId);
    return adb.run(['-s', deviceId, 'emu', 'kill']);
  }

  void _validate(String deviceId) {
    if (!RegExp(r'^emulator-\d+$').hasMatch(deviceId)) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'Expected emulator serial',
      );
    }
  }
}
