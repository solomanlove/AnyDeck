part of 'device_registry_providers.dart';

/// 设备注册表项目级操作混入（别名、备注、标签、勾选与删除）。
mixin DeviceRegistryItemActionsMixin on Notifier<List<RegisteredDevice>> {
  DeviceRegistryStorage get _storage;
  List<String> get _historyIds;
  Map<String, String> get _aliases;
  Map<String, String> get _models;
  Map<String, String> get _products;
  Map<String, String> get _ipAddresses;
  Map<String, String> get _androidVersions;
  Map<String, int> get _sdkVersions;
  Map<String, String> get _remarks;
  Map<String, List<String>> get _tags;
  Set<String> get _checkedIds;
  set _checkedIds(Set<String> v);
  Map<String, String> get _serialMap;
  List<AdbDevice> get _lastActiveDevices;
  set _lastActiveDevices(List<AdbDevice> v);
  Set<String> get _pendingFetchIds;
  Set<String> get _attemptedFetchIds;
  List<RegisteredDevice> _mergeDevices(List<AdbDevice> activeDevices);
  /// 设置设备别名并保存
  Future<void> setAlias(String id, String alias) async {
    final serial = _serialMap[id] ?? id;
    final idsToAlias = _serialMap.entries
        .where((entry) => entry.value == serial)
        .map((entry) => entry.key)
        .toList();
    if (idsToAlias.isEmpty) {
      idsToAlias.add(id);
    }

    for (final aliasId in idsToAlias) {
      if (alias.trim().isEmpty) {
        _aliases.remove(aliasId);
      } else {
        _aliases[aliasId] = alias.trim();
      }
    }
    await _storage.saveAliases(_aliases);
    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  /// 更新用户备注并保存
  Future<void> updateRemark(String id, String remark) async {
    final targetIds = <String>{id};
    final serial = _serialMap[id] ?? id;
    targetIds.add(serial);
    for (final entry in _serialMap.entries) {
      if (entry.value == serial) {
        targetIds.add(entry.key);
      }
    }
    for (final dev in state) {
      if (dev.id == id || dev.serial == serial || dev.connections.contains(id)) {
        targetIds.add(dev.id);
        targetIds.addAll(dev.connections);
        if (dev.serial != null && dev.serial!.isNotEmpty) {
          targetIds.add(dev.serial!);
        }
      }
    }
    for (final targetId in targetIds) {
      if (remark.trim().isEmpty) {
        _remarks.remove(targetId);
      } else {
        _remarks[targetId] = remark.trim();
      }
    }
    await _storage.saveRemarks(_remarks);
    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  /// 更新设备标签并保存
  Future<void> updateTags(String id, List<String> tags) async {
    final targetIds = <String>{id};
    final serial = _serialMap[id] ?? id;
    targetIds.add(serial);
    for (final entry in _serialMap.entries) {
      if (entry.value == serial) {
        targetIds.add(entry.key);
      }
    }
    for (final dev in state) {
      if (dev.id == id || dev.serial == serial || dev.connections.contains(id)) {
        targetIds.add(dev.id);
        targetIds.addAll(dev.connections);
        if (dev.serial != null && dev.serial!.isNotEmpty) {
          targetIds.add(dev.serial!);
        }
      }
    }
    for (final targetId in targetIds) {
      if (tags.isEmpty) {
        _tags.remove(targetId);
      } else {
        _tags[targetId] = tags;
      }
    }
    await _storage.saveTags(_tags);
    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  /// 移除指定 ID 的设备记录
  Future<void> removeDevice(String id) {
    return _removeDevices({id});
  }

  /// 批量移除所有复选框选中的设备记录
  Future<void> removeCheckedDevices() {
    final checkedDeviceIds = state
        .where((device) => device.isChecked)
        .map((device) => device.id)
        .toSet();
    return _removeDevices(checkedDeviceIds);
  }

  Future<void> _removeDevices(Set<String> ids) async {
    if (ids.isEmpty) {
      return;
    }

    final idsToRemove = <String>{};
    for (final id in ids) {
      idsToRemove.add(id);
      for (final d in state) {
        if (d.id == id ||
            d.connections.contains(id) ||
            (d.serial != null && d.serial == id)) {
          idsToRemove.add(d.id);
          idsToRemove.addAll(d.connections);
          if (d.serial != null && d.serial!.isNotEmpty) {
            idsToRemove.add(d.serial!);
          }
        }
      }

      final serial = _serialMap[id] ?? id;
      final sameSerialIds = _serialMap.entries
          .where((entry) => entry.value == serial)
          .map((entry) => entry.key)
          .toSet();
      idsToRemove.addAll(sameSerialIds);
    }

    final disconnectFutures = <Future<void>>[];
    for (final removeId in idsToRemove) {
      final isNetwork = DeviceRegistryStorage.isNetworkId(removeId);
      if (isNetwork) {
        disconnectFutures.add(
          ref
              .read(deviceActionServiceProvider)
              .disconnect(removeId)
              .then((_) {})
              .catchError((_) {}),
        );
      }
    }
    if (disconnectFutures.isNotEmpty) {
      await Future.wait(disconnectFutures);
    }

    for (final removeId in idsToRemove) {
      final selected = ref.read(selectedDeviceProvider);
      if (selected != null &&
          (selected.id == removeId || idsToRemove.contains(selected.id))) {
        ref.read(selectedDeviceProvider.notifier).clear();
      }

      _historyIds.remove(removeId);
      _checkedIds.remove(removeId);
      _aliases.remove(removeId);
      _models.remove(removeId);
      _products.remove(removeId);
      _ipAddresses.remove(removeId);
      _androidVersions.remove(removeId);
      _sdkVersions.remove(removeId);
      _remarks.remove(removeId);
      _tags.remove(removeId);
      _serialMap.remove(removeId);
      _pendingFetchIds.remove(removeId);
      _attemptedFetchIds.remove(removeId);

      // 级联彻底清理设备概览、应用图标目录、常用文件夹与 SQLite 数据库等全部缓存
      await DeviceRegistryCleaner.cleanupAll(ref, removeId);
    }

    await _storage.saveHistory(_historyIds);
    await _storage.saveAliases(_aliases);
    await _storage.saveModelsAndProducts(_models, _products);
    await _storage.saveIps(_ipAddresses);
    await _storage.saveAndroidVersions(_androidVersions, _sdkVersions);
    await _storage.saveRemarks(_remarks);
    await _storage.saveTags(_tags);

    var activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    activeDevices = activeDevices
        .where((d) => !idsToRemove.contains(d.id))
        .toList();
    _lastActiveDevices = activeDevices;
    state = _mergeDevices(activeDevices);
    ref.read(adbHeartbeatControllerProvider).trigger();
  }

  /// 切换指定设备代表项的选中状态
  void toggleCheck(String id) {
    final serial = _serialMap[id] ?? id;
    final idsToToggle = _serialMap.entries
        .where((entry) => entry.value == serial)
        .map((entry) => entry.key)
        .toSet();
    idsToToggle.add(id);
    for (final d in state) {
      if (d.id == id ||
          d.connections.contains(id) ||
          d.serial == id ||
          (d.serial != null && d.serial == serial)) {
        idsToToggle.add(d.id);
        idsToToggle.addAll(d.connections);
      }
    }

    final isRepresentativeChecked = _checkedIds.contains(id) ||
        state
            .where((d) => d.id == id || d.connections.contains(id))
            .any((d) => d.isChecked);
    for (final toggleId in idsToToggle) {
      if (isRepresentativeChecked) {
        _checkedIds.remove(toggleId);
      } else {
        _checkedIds.add(toggleId);
      }
    }

    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  /// 全选或全不选所有设备代表项
  void toggleAll(bool checked) {
    if (checked) {
      final allRepresentedSerials = state
          .map((d) => _serialMap[d.id] ?? d.id)
          .toSet();
      _checkedIds = _serialMap.entries
          .where((entry) => allRepresentedSerials.contains(entry.value))
          .map((entry) => entry.key)
          .toSet();
      for (final d in state) {
        _checkedIds.add(d.id);
        _checkedIds.addAll(d.connections);
        if (d.serial != null && d.serial!.isNotEmpty) {
          _checkedIds.add(d.serial!);
        }
      }
    } else {
      _checkedIds.clear();
    }
    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }
}
