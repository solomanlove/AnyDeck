import '../adb/adb_device.dart';
import '../adb/adb_service.dart';
import '../adb/wireless/adb_wireless_probe.dart';
import '../adb/wireless/adb_wireless_state.dart';

/// 投屏断线时按硬件序列号查找同一手机的最新在线 ADB transport。
/// 仅使用已连接的 USB/TCP/TLS 通道，不启用无线调试或连接历史 IP。
class MirrorTransportResolver {
  MirrorTransportResolver(this.adb, this.initialDeviceId) {
    if (!_isNetwork(initialDeviceId)) _serial = initialDeviceId;
    _identity = _rememberIdentity();
  }

  final AdbService adb;
  final String initialDeviceId;
  String? _serial;
  late final Future<void> _identity;
  bool _cancelled = false;

  static bool _isNetwork(String id) => id.contains(':') || id.contains('.');

  Future<void> _rememberIdentity() async {
    if (_serial != null) return;
    final probe = AdbWirelessProbe(adb, isCancelled: () => _cancelled);
    _serial = await probe.serial(initialDeviceId);
  }

  /// 新鲜列表中的候选仍须回读序列号，防止 DHCP 地址复用后投到其他手机。
  Future<String?> resolve({required Set<String> excluded}) async {
    await _identity;
    if (_cancelled || _serial == null) return null;
    final elapsed = Stopwatch()..start();
    Duration remaining() => const Duration(seconds: 6) - elapsed.elapsed;
    final probe = AdbWirelessProbe(adb, isCancelled: () => _cancelled);
    final result = await probe.run(['devices', '-l']);
    if (_cancelled || !result.isSuccess) return null;
    final candidates = result.stdout
        .split('\n')
        .skipWhile((line) => !line.startsWith('List of devices attached'))
        .skip(1)
        .where((line) => line.trim().isNotEmpty)
        .map(adb.parseDeviceLine)
        .whereType<AdbDevice>()
        .where((device) => device.isOnline && !excluded.contains(device.id))
        .toList();
    int priority(AdbDevice device) =>
        !_isNetwork(device.id) ? 0 : (isWirelessTlsId(device.id) ? 2 : 1);
    candidates.sort((a, b) => priority(a).compareTo(priority(b)));
    for (final candidate in candidates) {
      if (_cancelled || remaining() <= Duration.zero) return null;
      final serial = await probe.serial(
        candidate.id,
        remaining: () => remaining() < const Duration(seconds: 2)
            ? remaining()
            : const Duration(seconds: 2),
      );
      if (!_cancelled && serial == _serial) return candidate.id;
    }
    return null;
  }

  /// 窗口关闭后不再继续查询或应用迟到的连接结果。
  void dispose() => _cancelled = true;
}
