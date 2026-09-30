import '../adb_result.dart';
import '../adb_service.dart';
import 'adb_wireless_state.dart';

/// 无线连接的有界 ADB 探测；不读取旧 IP 缓存，也不使用 Ping 阻断连接。
class AdbWirelessProbe {
  AdbWirelessProbe(this.adb, {this.isCancelled});
  final AdbService adb;
  final bool Function()? isCancelled;
  bool get cancelled => isCancelled?.call() ?? false;

  Future<AdbResult> run(List<String> args, {Duration? timeout}) async {
    if (cancelled) return const AdbWirelessResult('wirelessCancelled');
    if (timeout != null && timeout <= Duration.zero) {
      return const AdbWirelessResult('wirelessFailed');
    }
    return adb.run(args, timeout: timeout ?? const Duration(seconds: 3));
  }

  Future<String?> serial(String id, {Duration Function()? remaining}) async {
    for (final property in ['ro.serialno', 'ro.boot.serialno']) {
      final result = await run([
        '-s',
        id,
        'shell',
        'getprop',
        property,
      ], timeout: remaining?.call());
      final value = result.stdout.trim();
      if (result.isSuccess &&
          value.isNotEmpty &&
          value != 'unknown' &&
          value != '-') {
        return value;
      }
    }
    return null;
  }

  Future<bool> online(String id, {Duration? timeout}) async {
    final result = await run(['-s', id, 'get-state'], timeout: timeout);
    return result.isSuccess && result.stdout.trim() == 'device';
  }

  /// 只从 Wi-Fi 接口取地址，避免选择 VPN、蜂窝网络或默认网关。
  Future<String?> ip(String id, {Duration Function()? remaining}) async {
    final route = await run([
      '-s',
      id,
      'shell',
      'ip',
      '-4',
      'route',
    ], timeout: remaining?.call());
    if (route.isSuccess) {
      final found = parseWifiRoute(route.stdout);
      if (found != null) return found;
    }
    final addr = await run([
      '-s',
      id,
      'shell',
      'ip',
      '-o',
      '-4',
      'addr',
      'show',
    ], timeout: remaining?.call());
    return addr.isSuccess ? parseWifiAddress(addr.stdout) : null;
  }

  static String? parseWifiRoute(String text) {
    for (final line in text.split('\n')) {
      if (!RegExp(r'\bdev\s+(?:wlan|wifi|swlan)\S*\b').hasMatch(line)) continue;
      final src = RegExp(r'\bsrc\s+(\d+\.\d+\.\d+\.\d+)').firstMatch(line);
      final value = wirelessIpv4(src?[1]);
      if (value != null) return value;
    }
    return null;
  }

  static String? parseWifiAddress(String text) {
    for (final line in text.split('\n')) {
      final match = RegExp(
        r'^\s*\d+:\s+(?:wlan|wifi|swlan)\S*\s+inet\s+(\d+\.\d+\.\d+\.\d+)/',
      ).firstMatch(line);
      final value = wirelessIpv4(match?[1]);
      if (value != null) return value;
    }
    return null;
  }

  Future<List<AdbMdnsEndpoint>> discover() async {
    final result = await run(['mdns', 'services']);
    return result.isSuccess ? AdbMdnsEndpoint.parse(result.stdout) : [];
  }

  /// connect 的退出码不能证明 transport 可用，必须回读状态并校验身份。
  Future<bool> connect(String address, String? expectedSerial) async {
    final wasOnline = await online(address);
    await run(['connect', address]);
    if (!await online(address)) return false;
    final actual = await serial(address);
    final matches =
        actual != null && (expectedSerial == null || actual == expectedSerial);
    if (!matches && !wasOnline) await run(['disconnect', address]);
    return matches;
  }
}
