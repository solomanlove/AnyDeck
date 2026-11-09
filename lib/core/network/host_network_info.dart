/// 宿主机网络快照；Wi-Fi 名称不可读与未连接必须分别展示。
enum HostWifiStatus { connected, disconnected, permissionRequired, unavailable }

/// 将网卡与 IPv4 绑定，避免将 VPN 或其他网卡的地址误标为 Wi-Fi 地址。
class HostNetworkAddress {
  const HostNetworkAddress(this.interfaceName, this.ipv4);

  final String interfaceName;
  final String ipv4;
}

/// 宿主机网络快照；选定 Wi-Fi 仅在用户启用自动共享规则后由共享模块另行保存。
class HostNetworkInfo {
  const HostNetworkInfo({
    this.wifiStatus = HostWifiStatus.unavailable,
    this.ssid,
    this.verifiedWifiSsid,
    this.address,
    this.isWifiAddress = false,
    this.ipv4Addresses = const [],
  });

  final HostWifiStatus wifiStatus;
  final String? ssid;
  /// 仅来自系统当前关联结果；自动共享不能使用扫描缓存推测出的 SSID。
  final String? verifiedWifiSsid;
  final HostNetworkAddress? address;
  final bool isWifiAddress;

  /// 本轮读取的所有有效网卡地址，供设备行与底栏共享；多网卡任一匹配即可。
  final List<HostNetworkAddress> ipv4Addresses;

  /// 优先选择已连接 Wi-Fi 的 IPv4，再选择物理有线网卡；忽略虚拟网卡。
  static HostNetworkInfo resolve(
    Map<Object?, Object?>? snapshot,
    List<HostNetworkAddress> addresses,
  ) {
    final usable = addresses.where((entry) {
      final parts = entry.ipv4.split('.').map(int.tryParse).toList();
      return parts.length == 4 &&
          parts.every((part) => part != null && part >= 0 && part <= 255) &&
          parts[0] != 0 &&
          parts[0] != 127 &&
          parts[0]! < 224 &&
          !(parts[0] == 169 && parts[1] == 254);
    }).toList();
    final wifi = (snapshot?['wifiInterfaces'] as List? ?? [])
        .whereType<Map>()
        .where((entry) => entry['connected'] == true)
        .toList();
    Map? selectedWifi;
    HostNetworkAddress? address;
    for (final entry in wifi) {
      selectedWifi ??= entry;
      for (final candidate in usable) {
        if (candidate.interfaceName == entry['name']) {
          selectedWifi = entry;
          address = candidate;
          break;
        }
      }
      if (address != null) break;
    }
    final isWifiAddress = address != null;
    final physical = snapshot?['physicalInterfaces'] as List?;
    address ??= usable.where((entry) {
      if (physical != null) return physical.contains(entry.interfaceName);
      // 原生桥不可用的平台只采用常见物理网卡名，不猜测 VPN 地址。
      return RegExp(
        r'^(en\d|eth\d|eno\d|ens\d|enp\d|wlan\d|wlp\d|wlx|wi-fi|ethernet)',
        caseSensitive: false,
      ).hasMatch(entry.interfaceName);
    }).firstOrNull;
    final ssid = selectedWifi?['ssid'] as String?;
    final hasSsid = ssid != null && ssid.isNotEmpty;
    final status = hasSsid
        ? HostWifiStatus.connected
        : snapshot == null
        ? HostWifiStatus.unavailable
        : selectedWifi == null
        ? HostWifiStatus.disconnected
        : snapshot['locationAuthorized'] != true
        ? HostWifiStatus.permissionRequired
        : HostWifiStatus.unavailable;
    return HostNetworkInfo(
      wifiStatus: status,
      ssid: hasSsid ? ssid : null,
      verifiedWifiSsid: (selectedWifi?['verifiedSsid'] as String?)?.isNotEmpty == true
          ? selectedWifi!['verifiedSsid'] as String : null,
      address: address,
      isWifiAddress: isWifiAddress,
      ipv4Addresses: List.unmodifiable(usable),
    );
  }
}
