import 'dart:io';

/// 局域网网络检测工具类，用于判断手机与电脑是否在同一局域网并提供 Ping 连通性测试。
class NetworkLanMatcher {
  /// 获取当前电脑优先用于手机访问的局域网 IPv4 地址。
  static Future<String?> preferredHostIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      String? fallback;
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (_isLinkLocal(ip)) {
            continue;
          }
          fallback ??= ip;
          if (_isPrivateIpv4(ip)) {
            return ip;
          }
        }
      }
      return fallback;
    } catch (_) {
      return null;
    }
  }

  /// 方法一：读取本机 IPv4 后估算网段；连接流程沿用未知时返回 false 的行为。
  static Future<bool> isSameSubnet(String phoneIp) async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return matchesAnySubnet(
            phoneIp,
            interfaces.expand((entry) => entry.addresses.map((a) => a.address)),
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 用同一份网络快照估算网段；地址无效或本机地址未知时返回 null，避免误报。
  /// 未读取实际掩码，沿用 /24、私有 10/8 和 172.16/12 的提示性规则。
  static bool? matchesAnySubnet(String phoneIp, Iterable<String> hostIps) {
    final phoneParts = _ipv4Parts(phoneIp);
    if (phoneParts == null) return null;
    var hasHostAddress = false;
    for (final hostIp in hostIps) {
      final pcParts = _ipv4Parts(hostIp);
      if (pcParts == null) continue;
      hasHostAddress = true;
      if (phoneParts[0] == pcParts[0] &&
          phoneParts[1] == pcParts[1] &&
          phoneParts[2] == pcParts[2]) {
        return true;
      }
      if (phoneParts[0] == 10 && pcParts[0] == 10) return true;
      if (phoneParts[0] == 172 &&
          pcParts[0] == 172 &&
          phoneParts[1] >= 16 &&
          phoneParts[1] <= 31 &&
          pcParts[1] >= 16 &&
          pcParts[1] <= 31) {
        return true;
      }
    }
    return hasHostAddress ? false : null;
  }

  /// 排除占位符、回环、链路本地及非单播地址，未知状态不作为网段不匹配。
  static List<int>? _ipv4Parts(String ip) {
    final address = InternetAddress.tryParse(ip);
    if (address == null || address.type != InternetAddressType.IPv4) {
      return null;
    }
    final parts = address.rawAddress;
    if (parts[0] == 0 ||
        parts[0] == 127 ||
        parts[0] >= 224 ||
        (parts[0] == 169 && parts[1] == 254)) {
      return null;
    }
    return parts;
  }

  /// 方法二：动态测试网络可达性 (Ping 手机 IP)
  static Future<bool> pingDevice(String phoneIp) async {
    if (phoneIp == '-' || phoneIp.isEmpty) return false;
    try {
      // 视操作系统执行不同的 ping 命令参数（发送1个包，超时限制1秒）
      final result = Platform.isWindows
          ? await Process.run('ping', ['-n', '1', '-w', '1000', phoneIp])
          : await Process.run('ping', ['-c', '1', '-t', '1', phoneIp]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static bool _isPrivateIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    if (first == null || second == null) return false;
    if (first == 10) return true;
    if (first == 172 && second >= 16 && second <= 31) return true;
    if (first == 192 && second == 168) return true;
    return false;
  }

  static bool _isLinkLocal(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    return parts[0] == '169' && parts[1] == '254';
  }
}
