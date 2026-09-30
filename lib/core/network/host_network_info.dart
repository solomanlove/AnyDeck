/// 宿主机网络快照；Wi-Fi 名称不可读与未连接必须分别展示。
enum HostWifiStatus { connected, disconnected, permissionRequired, unavailable }

/// 将网卡与 IPv4 绑定，避免将 VPN 或其他网卡的地址误标为 Wi-Fi 地址。
class HostNetworkAddress {
  const HostNetworkAddress(this.interfaceName, this.ipv4);

  final String interfaceName;
  final String ipv4;
}

/// 设备列表底部使用的宿主机网络信息，不保存网络名称或地址到磁盘。
class HostNetworkInfo {
  const HostNetworkInfo({
    this.wifiStatus = HostWifiStatus.unavailable,
    this.ssid,
    this.address,
    this.isWifiAddress = false,
  });

  final HostWifiStatus wifiStatus;
  final String? ssid;
  final HostNetworkAddress? address;
  final bool isWifiAddress;

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
      address: address,
      isWifiAddress: isWifiAddress,
    );
  }
}
