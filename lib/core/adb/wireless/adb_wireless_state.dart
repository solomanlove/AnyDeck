import '../adb_result.dart';

/// 单设备连接阶段；messageKey 交由界面按当前语言翻译。
class AdbWirelessState {
  const AdbWirelessState({
    required this.deviceId,
    required this.messageKey,
    this.busy = false,
    this.failed = false,
    this.ip,
    this.serial,
  });

  final String deviceId;
  final String messageKey;
  final bool busy;
  final bool failed;
  final String? ip;
  final String? serial;

  /// Wi-Fi 地址获取失败时显式清空旧缓存，避免列表继续展示上一个网络的 IP。
  String? get registryIp => messageKey == 'wirelessNoIp' ? '-' : ip;
}

/// 连接结果保留诊断原文，UI 使用本地化提示。
class AdbWirelessResult extends AdbResult {
  const AdbWirelessResult(
    this.messageKey, {
    bool success = false,
    String detail = '',
  }) : super(exitCode: success ? 0 : 1, stdout: detail, stderr: '');

  final String messageKey;
}

/// mDNS 服务类型与地址，解析时保留带空格的实例名。
class AdbMdnsEndpoint {
  const AdbMdnsEndpoint(this.name, this.type, this.address);
  final String name;
  final String type;
  final String address;
  bool get isTls => type == '_adb-tls-connect._tcp';
  String get ip => address.substring(0, address.lastIndexOf(':'));

  bool matches(String? serial, String? ipAddress) =>
      (serial != null &&
          (name == 'adb-$serial' || name.startsWith('adb-$serial-'))) ||
      (ipAddress != null && ip == ipAddress);

  static List<AdbMdnsEndpoint> parse(String output) {
    final pattern = RegExp(
      r'^(.+?)\s+(_adb(?:-tls-connect)?\._tcp)\.?\s+(\d+\.\d+\.\d+\.\d+:\d+)\s*$',
    );
    return [
      for (final line in output.split('\n'))
        if (pattern.firstMatch(line.trim()) case final match?)
          AdbMdnsEndpoint(match[1]!, match[2]!, match[3]!),
    ];
  }
}

/// 排除 mDNS 实例名、模拟器与非法地址，避免当作手机 IPv4 使用。
String? wirelessIpv4(String? value) {
  if (value == null) return null;
  final parts = value.split('.');
  if (parts.length != 4) return null;
  final octets = parts.map(int.tryParse).toList();
  if (octets.any((p) => p == null || p < 0 || p > 255)) return null;
  if (octets.first == 0 || octets.first == 127 || octets.first! >= 224) {
    return null;
  }
  return value;
}

/// mDNS 类型优先于端口猜测，避免 TLS 服务名被误认为传统 TCP/IP。
bool isWirelessTlsId(String id) =>
    id.contains('_adb-tls-connect._tcp') ||
    (!id.contains('._adb._tcp') &&
        id.contains(':') &&
        int.tryParse(id.split(':').last) != 5555);

bool isPhysicalUsbId(String id) =>
    id.isNotEmpty &&
    !id.contains(':') &&
    !id.contains('.') &&
    !id.startsWith('emulator-');
