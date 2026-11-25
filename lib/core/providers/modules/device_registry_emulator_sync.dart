part of 'device_registry_providers.dart';

/// 将 AVD 身份接入注册表，实际命令仍以选中的 transport ID 执行。
extension _DeviceRegistryEmulatorSync on DeviceRegistryNotifier {
  Map<String, String> _syncEmulatorRecords(Ref ref, List<DiscoveredDevice> active) {
    _emulators.observe(
      active,
      EmulatorConnectionService(ref.read(adbServiceProvider)),
      _onEmulatorIdentified,
      () => !_isDisposed,
    );
    final names = _emulators.namesById(_historyIds);
    final represented = names.values.toSet();
    final activeIds = active.map((device) => device.id).toSet();
    final histories = _emulators.historyByName;
    for (final name in _emulators.confirmedNames.difference(represented)) {
      // 未完成身份查询时，暂用当前端口行展示，避免同一连接重复出现。
      if (histories[name]!.any(
        (id) => activeIds.contains(id) && !names.containsKey(id),
      )) {
        continue;
      }
      names[DeviceRegistryEmulators.keyFor(name)] = name;
    }

    _serialMap.removeWhere(
      (id, _) =>
          EmulatorConnectionService.isTransport(id) ||
          id.startsWith('emulator-avd-'),
    );
    for (final entry in names.entries) {
      final key = DeviceRegistryEmulators.keyFor(entry.value);
      _serialMap[entry.key] = key;
      _serialMap[key] = key;
    }
    return names;
  }

  void _onEmulatorIdentified(String id, String? previousName, String name) {
    if (_isDisposed) return;
    if (previousName != null && previousName != name) {
      _emulatorEditRevision++;
      // 端口复用后，旧 AVD 的用户编辑留在稳定键下。
      final key = DeviceRegistryEmulators.keyFor(previousName);
      _preserveEmulatorEdit(_aliases, id, key);
      _preserveEmulatorEdit(_remarks, id, key);
      _preserveEmulatorEdit(_tags, id, key);
      unawaited(_storage.saveAliases(_aliases));
      unawaited(_storage.saveRemarks(_remarks));
      unawaited(_storage.saveTags(_tags));
    }
    _publishRegistrySnapshot(_lastActiveDevices);
  }

  void _preserveEmulatorEdit<T>(Map<String, T> data, String id, String key) {
    final value = data.remove(id);
    if (value != null) data.putIfAbsent(key, () => value);
  }

  void _scheduleDeviceMetadataProbe(String id) {
    Future.microtask(() async {
      final activeDevs = _registryRef.read(discoveredDevicesProvider).value ?? _lastActiveDevices;
      final dev = activeDevs.firstWhere(
        (d) => d.id == id,
        orElse: () => DiscoveredDevice(id: id, status: 'offline', model: '', product: ''),
      );

      if (dev.isHarmony) {
        _scheduleHarmonyMetadataProbe(id);
        return;
      }

      try {
        await _registryRef.read(adbWirelessConnectionProvider.notifier).waitForPreparation(id);
        if (_isDisposed) return;
        final adb = _registryRef.read(adbServiceProvider);
        await DeviceMetadataProbeService.probeAndSyncAndroid(
          adb: adb,
          id: id,
          androidVersions: _androidVersions,
          sdkVersions: _sdkVersions,
          serialMap: _serialMap,
          ipAddresses: _ipAddresses,
          storage: _storage,
        );
      } finally {
        _pendingFetchIds.remove(id);
        _attemptedFetchIds.add(id);
        if (!_isDisposed) {
          final activeDevices =
              _registryRef.read(discoveredDevicesProvider).value ?? _lastActiveDevices;
          _publishRegistrySnapshot(activeDevices);
        }
      }
    });
  }
}
