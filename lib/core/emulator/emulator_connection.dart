import '../adb/discovered_device.dart';
import '../adb/adb_result.dart';
import '../adb/adb_service.dart';

/// AVD 曾用端口与最近一次连接的起止时间。未观察到的时间为空。
typedef EmulatorConnectionHistoryEntry = ({
  String id,
  DateTime? connectedAt,
  DateTime? disconnectedAt,
});

/// AVD 与 ADB transport 的关联；console 查询不依赖 Android shell 授权。
class EmulatorConnectionService {
  const EmulatorConnectionService(this.adb);

  final AdbService adb;

  Future<Map<String, DiscoveredDevice>> inspect(List<DiscoveredDevice> devices) async {
    final result = <String, DiscoveredDevice>{};
    for (final device in devices) {
      final name = await identify(device);
      if (name != null) result[name] = device;
    }
    return result;
  }

  /// 读取当前 transport 对应的 AVD 名称，兼容未授权状态和旧 console。
  Future<String?> identify(DiscoveredDevice device) async {
    if (device.isIos || device.isHarmony || !isTransport(device.id)) return null;
    final response = await adb.run([
      '-s',
      device.id,
      'emu',
      'avd',
      'name',
    ], timeout: const Duration(seconds: 3));
    final name = response.isSuccess ? parseAvdName(response.stdout) : null;
    if (name != null || !device.isOnline) return name;
    for (final property in [
      'ro.boot.qemu.avd_name',
      'ro.kernel.qemu.avd_name',
    ]) {
      final value = await adb.shellArgs(device.id, ['getprop', property]);
      final candidate = value.isSuccess ? parseAvdName(value.stdout) : null;
      if (candidate != null) return candidate;
    }
    return null;
  }

  static final _transportPattern = RegExp(r'^emulator-\d+$');
  static final _namePattern = RegExp(r'^[\w.\-]+$');

  /// ADB 分配给本地模拟器的端口标识。
  static bool isTransport(String id) => _transportPattern.hasMatch(id);

  /// AVD 名称可用作本地配置标识。
  static bool isAvdName(String value) => _namePattern.hasMatch(value);

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
        .where(isAvdName)
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
    if (!isTransport(deviceId)) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'Expected emulator serial',
      );
    }
  }
}
