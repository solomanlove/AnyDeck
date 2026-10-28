import 'dart:io';

/// 供私有核心使用的本机 IPv4 与广播地址，不暴露给普通界面。
class ShareNetwork {
  const ShareNetwork(this.local, this.broadcast);

  final InternetAddress local;
  final InternetAddress broadcast;

  /// 按网卡真实 netmask 计算广播地址，避免假定所有 Wi-Fi 都是 /24。
  static InternetAddress broadcastFor(InternetAddress address, int mask) {
    final octets = address.rawAddress;
    final value =
        (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];
    final broadcast = value | (~mask & 0xffffffff);
    return InternetAddress(
      '${(broadcast >> 24) & 255}.'
      '${(broadcast >> 16) & 255}.${(broadcast >> 8) & 255}.'
      '${broadcast & 255}',
    );
  }

  static Future<ShareNetwork> detect() async {
    if (!Platform.isMacOS) throw const FileSystemException('macOS required');
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final ordered = [...interfaces]
      ..sort((a, b) {
        final aRank = a.name == 'en0' ? 0 : 1;
        final bRank = b.name == 'en0' ? 0 : 1;
        return aRank.compareTo(bRank);
      });
    for (final interface in ordered) {
      final address = interface.addresses
          .where((a) => !a.isLoopback && !a.isLinkLocal)
          .firstOrNull;
      if (address == null) continue;
      final result = await Process.run('/sbin/ifconfig', [interface.name]);
      if (result.exitCode != 0) continue;
      final escaped = RegExp.escape(address.address);
      final match = RegExp(
        'inet $escaped netmask (0x[0-9a-fA-F]+)',
      ).firstMatch(result.stdout.toString());
      if (match == null) continue;
      final mask = int.tryParse(match.group(1)!.substring(2), radix: 16);
      if (mask == null || mask == 0 || mask == 0xffffffff) continue;
      return ShareNetwork(address, broadcastFor(address, mask));
    }
    throw const FileSystemException('No active IPv4 network with netmask');
  }
}
