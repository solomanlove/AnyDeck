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

  /// 方法一：判断手机 IP 与电脑的所有物理网卡 IPv4 是否在同一局域网网段
  static Future<bool> isSameSubnet(String phoneIp) async {
    if (phoneIp == '-' || phoneIp.isEmpty) return false;

    try {
      // 获取电脑上所有非回环的 IPv4 地址列表
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      final phoneParts = phoneIp.split('.');
      if (phoneParts.length != 4) return false;

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final pcIp = addr.address;
          final pcParts = pcIp.split('.');
          if (pcParts.length != 4) continue;

          // C 类私有网段匹配 (掩码 255.255.255.0 /24)
          if (phoneParts[0] == pcParts[0] &&
              phoneParts[1] == pcParts[1] &&
              phoneParts[2] == pcParts[2]) {
            return true;
          }

          // A 类私有网段匹配 (10.x.x.x，掩码 255.0.0.0 /8)
          if (phoneParts[0] == '10' && pcParts[0] == '10') {
            return true;
          }

          // B 类私有网段匹配 (172.16.0.0 - 172.31.255.255，掩码 255.240.0.0 /12)
          if (phoneParts[0] == '172' && pcParts[0] == '172') {
            final phoneSeg = int.tryParse(phoneParts[1]);
            final pcSeg = int.tryParse(pcParts[1]);
            if (phoneSeg != null &&
                pcSeg != null &&
                phoneSeg >= 16 &&
                phoneSeg <= 31 &&
                pcSeg >= 16 &&
                pcSeg <= 31) {
              return true;
            }
          }
        }
      }
    } catch (_) {}
    return false;
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
