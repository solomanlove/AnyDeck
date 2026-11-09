part of 'device_registry_providers.dart';

/// 将 ADB/HDC 实时网络结果同步到注册表，并保护异步磁盘加载顺序。
extension _DeviceRegistryIpSync on DeviceRegistryNotifier {
  void _listenWirelessState(Ref ref) {
    ref.listen(harmonyDeviceIpsProvider, (previous, next) {
      if (_isDisposed) return;
      for (final entry in (next.value ?? const <String, String>{}).entries) {
        updateDeviceIp(entry.key, entry.value, clear: entry.value == '-');
      }
    });
    ref.listen(adbWirelessConnectionProvider, (previous, next) {
      for (final entry in next.entries) {
        if (identical(previous?[entry.key], entry.value)) continue;
        final value = entry.value;
        if (value.registryIp == null || value.busy) continue;
        if (_isDisposed) return;
        updateDeviceIp(
          value.deviceId,
          value.registryIp!,
          clear: value.registryIp == '-',
        );
        if (value.serial != null && value.serial != value.deviceId) {
          updateDeviceIp(
            value.serial!,
            value.registryIp!,
            clear: value.registryIp == '-',
          );
        }
      }
    });
  }

  void _restoreLiveDeviceIps(Ref ref) {
    // 实时连接结果优先于异步加载的磁盘快照，避免 DHCP 更新被旧缓存覆盖。
    for (final value in ref.read(adbWirelessConnectionProvider).values) {
      if (value.registryIp == null || value.busy) continue;
      _ipAddresses[value.deviceId] = value.registryIp!;
      if (value.serial != null) _ipAddresses[value.serial!] = value.registryIp!;
    }
    // HDC 实时 WLAN 结果同样优先于磁盘快照，包括 Wi-Fi 断开后的清空状态。
    for (final entry
        in (ref.read(harmonyDeviceIpsProvider).value ??
                const <String, String>{})
            .entries) {
      _ipAddresses[entry.key] = entry.value;
      final serial = _serialMap[entry.key];
      if (serial != null) _ipAddresses[serial] = entry.value;
    }
  }
}
