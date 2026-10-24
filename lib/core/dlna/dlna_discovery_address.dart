import 'dart:io';

/// 按系统路由选择 SSDP LOCATION 的本机地址，避免向局域网手机广播 VPN 地址。
class DlnaDiscoveryAddress {
  static InternetAddress? select(
    String routeOutput,
    InternetAddress destination,
    Map<String, List<InternetAddress>> interfaces,
  ) {
    final name = RegExp(
      r'^\s*interface:\s*(\S+)',
      multiLine: true,
    ).firstMatch(routeOutput)?.group(1);
    final addresses = interfaces[name]
        ?.where((address) => !address.isLoopback && !address.isLinkLocal)
        .toList();
    if (addresses == null || addresses.isEmpty) return null;

    final localAddress = RegExp(
      r'^\s*local addr:\s*(\S+)',
      multiLine: true,
    ).firstMatch(routeOutput)?.group(1);
    for (final address in addresses) {
      if (address.address == localAddress) return address;
    }
    for (final address in addresses) {
      final local = address.rawAddress;
      final remote = destination.rawAddress;
      if (local.length == 4 &&
          remote.length == 4 &&
          local[0] == remote[0] &&
          local[1] == remote[1] &&
          local[2] == remote[2]) {
        return address;
      }
    }
    return addresses.first;
  }
}
