import 'dart:io';

/// 校验手动连接地址，避免将命令、无效 IP 或端口传给连接服务。
class NetworkDeviceAddress {
  const NetworkDeviceAddress(this.host, this.port);

  final String host;
  final int port;

  String get address => host.contains(':') ? '[$host]:$port' : '$host:$port';

  /// 支持 IP / 主机名及可选端口；省略端口时沿用 ADB 的 5555。
  static NetworkDeviceAddress? tryParse(String input) {
    final value = input.trim();
    final match =
        (value.startsWith('[')
                ? RegExp(r'^\[([^\]]+)\](?::([0-9]+))?$')
                : RegExp(r'^([^:\s]+)(?::([0-9]+))?$'))
            .firstMatch(value);
    if (match == null) return null;
    final host = match.group(1)!;
    final port = int.tryParse(match.group(2) ?? '5555');
    if (port == null || port < 1 || port > 65535) return null;
    final ip = InternetAddress.tryParse(host);
    if (ip == null) {
      if (value.startsWith('[') ||
          host.length > 253 ||
          RegExp(r'^[0-9.]+$').hasMatch(host)) {
        return null;
      }
      final label = RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$');
      if (host
          .split('.')
          .any((part) => part.length > 63 || !label.hasMatch(part))) {
        return null;
      }
    }
    return NetworkDeviceAddress(host, port);
  }
}
