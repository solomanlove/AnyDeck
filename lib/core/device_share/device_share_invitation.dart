import 'dart:io';
import 'dart:math';
import 'dart:convert';

/// 临时分享凭据：包含连接地址、证书 SHA-256 和 256 bit 随机令牌。
class DeviceShareInvitation {
  const DeviceShareInvitation({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.token,
    required this.name,
  });

  final String host;
  final int port;
  final String fingerprint;
  final String token;
  final String name;

  static String createToken() {
    final random = Random.secure();
    return base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  String encode() => Uri(
    scheme: 'anydeck-share',
    host: host,
    port: port,
    queryParameters: {'v': '1', 'fp': fingerprint, 'key': token, 'name': name},
  ).toString();

  /// 仅接受数值 IPv4，防止分享码被当作 URL 请求、Shell 参数或任意协议执行。
  factory DeviceShareInvitation.parse(String input) {
    if (input.length > 2048) throw const FormatException('Invalid share code');
    final uri = Uri.parse(input.trim());
    final address = InternetAddress.tryParse(uri.host);
    final args = uri.queryParameters;
    if (uri.scheme != 'anydeck-share' ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535 ||
        address == null ||
        address.type != InternetAddressType.IPv4 ||
        address.rawAddress[0] == 0 ||
        address.rawAddress[0] >= 224 ||
        args['v'] != '1' ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(args['fp'] ?? '') ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(args['key'] ?? '') ||
        (args['name']?.length ?? 0) > 120 ||
        uri.queryParametersAll.values.any((values) => values.length != 1)) {
      throw const FormatException('Invalid share code');
    }
    return DeviceShareInvitation(
      host: uri.host,
      port: uri.port,
      fingerprint: args['fp']!,
      token: args['key']!,
      name: args['name'] ?? 'Android',
    );
  }
}
