import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../adb/discovered_device.dart';
import '../../emulator/android_emulator.dart';
import '../../emulator/emulator_connection.dart';
import 'device_registry_storage.dart';

typedef _Connection = ({String name, String id});
typedef _Transport = ({String? transportId, String status});

/// 保存 AVD 与已见端口的关联，支持同一端口被另一个 AVD 复用。
class DeviceRegistryEmulators {
  static const _historyKey = 'devices.emulatorConnections.v1';
  final _history = <_Connection>[];
  final _legacy = <String, String>{};
  final _transports = <String, _Transport>{};
  final _confirmed = <String, String>{};
  final _queries = <String, Object>{};
  SharedPreferences? _preferences;
  Future<void>? _loadFuture;
  Future<void> _writes = Future.value();

  /// 已认证的 AVD 使用稳定键保存编辑数据。该键不能作为 ADB 命令参数。
  static String keyFor(String name) =>
      'emulator-avd-${name.replaceAll('.', '%2E')}';

  Future<void> load(
    DeviceRegistryPrefsData data,
    Future<List<AndroidEmulator>> Function() listConfigured,
  ) => _loadFuture ??= _load(data, listConfigured);

  Future<void> _load(
    DeviceRegistryPrefsData data,
    Future<List<AndroidEmulator>> Function() listConfigured,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in prefs.getStringList(_historyKey) ?? const <String>[]) {
      try {
        final pair = jsonDecode(entry);
        if (pair is! List || pair.length != 2) continue;
        final [name, id] = pair;
        if (name is String &&
            id is String &&
            EmulatorConnectionService.isAvdName(name) &&
            EmulatorConnectionService.isTransport(id)) {
          _history.add((name: name, id: id));
        }
      } on FormatException {
        // 单个坏记录不影响其余连接。
      }
    }

    final known = _history.map((entry) => entry.id).toSet();
    final unboundIds = data.historyIds.where(
      (id) => EmulatorConnectionService.isTransport(id) && !known.contains(id),
    );
    if (unboundIds.isNotEmpty) {
      final inventory = await listConfigured();
      for (final id in unboundIds) {
        final product = data.products[id];
        final match = RegExp(
          r'^sdk_gphone(16k|64)_(arm64|x86_64)$',
        ).firstMatch(product ?? '');
        final sdk = data.sdkVersions[id];
        if (match == null ||
            sdk == null ||
            inventory.any((avd) => avd.config.isEmpty)) {
          continue;
        }
        final abi = match.group(2) == 'arm64' ? 'arm64-v8a' : 'x86_64';
        final is16k = match.group(1) == '16k';
        final candidates = inventory.where((avd) {
          final image = avd.config['image.sysdir.1']?.toLowerCase() ?? '';
          return image.isNotEmpty &&
              int.tryParse(avd.sdkVersion?.split('.').first ?? '') == sdk &&
              avd.abi == abi &&
              image.contains('16k') == is16k;
        });
        // 旧版只有系统镜像特征，唯一候选只用于展示，等待 console 真正确认。
        if (candidates.length == 1) _legacy[id] = candidates.single.name;
      }
    }
    _preferences = prefs;
  }

  /// 每个 transport 代次只探测一次；连接变化时忽略旧查询的返回值。
  void observe(
    List<DiscoveredDevice> devices,
    EmulatorConnectionService connection,
    void Function(String id, String? previousName, String name) onChanged,
    bool Function() isActive,
  ) {
    if (_preferences == null) return;
    final current = {
      for (final device in devices)
        if (!device.isIos &&
            !device.isHarmony &&
            EmulatorConnectionService.isTransport(device.id))
          device.id: (transportId: device.transportId, status: device.status),
    };
    for (final id in _transports.keys.toList()) {
      if (current[id] == _transports[id]) continue;
      _confirmed.remove(id);
      _queries.remove(id);
    }
    for (final device in devices) {
      final transport = current[device.id];
      if (transport == null || transport == _transports[device.id]) continue;
      final token = Object();
      _queries[device.id] = token;
      unawaited(_identify(connection, device, token, onChanged, isActive));
    }
    _transports
      ..clear()
      ..addAll(current);
  }

  Future<void> _identify(
    EmulatorConnectionService connection,
    DiscoveredDevice device,
    Object token,
    void Function(String id, String? previousName, String name) onChanged,
    bool Function() isActive,
  ) async {
    String? name;
    try {
      name = await connection.identify(device);
    } catch (_) {
      return;
    }
    if (name == null || _queries[device.id] != token || !isActive()) return;
    final previousName =
        _history.reversed
            .where((entry) => entry.id == device.id)
            .firstOrNull
            ?.name ??
        _legacy[device.id];
    _confirmed[device.id] = name;
    _legacy.remove(device.id);
    final entry = (name: name, id: device.id);
    _history
      ..remove(entry)
      ..add(entry);
    unawaited(_save());
    onChanged(device.id, previousName, name);
  }

  /// 当前传输必须经本轮确认，离线传输使用最后一次已知归属。
  Map<String, String> namesById(Iterable<String> ids) {
    final names = {
      ..._legacy,
      for (final entry in _history) entry.id: entry.name,
    };
    return {
      for (final id in ids)
        if ((_transports.containsKey(id) ? _confirmed[id] : names[id])
            case final String name)
          id: name,
    };
  }

  /// 依已见顺序列出每个 AVD 使用过的不同端口。
  Map<String, List<String>> get historyByName {
    final result = <String, Set<String>>{};
    for (final entry in _legacy.entries) {
      result.putIfAbsent(entry.value, () => {}).add(entry.key);
    }
    for (final entry in _history) {
      result.putIfAbsent(entry.name, () => {}).add(entry.id);
    }
    return result.map((name, ids) => MapEntry(name, List.unmodifiable(ids)));
  }

  /// 端口被另一个 AVD 使用后，为原 AVD 保留可编辑的离线记录。
  Set<String> get confirmedNames => _history.map((entry) => entry.name).toSet();

  Future<void> remove(Set<String> ids) async {
    final names = confirmedNames
        .where((name) => ids.contains(keyFor(name)))
        .toSet();
    final previous = _history.length;
    _history.removeWhere((entry) => names.contains(entry.name));
    _legacy.removeWhere(
      (id, name) => ids.contains(id) || ids.contains(keyFor(name)),
    );
    for (final id in ids) {
      _confirmed.remove(id);
      _queries.remove(id);
      _transports.remove(id);
    }
    if (_history.length != previous) await _save();
  }

  Future<void> _save() {
    final snapshot = [
      for (final entry in _history) jsonEncode([entry.name, entry.id]),
    ];
    return _writes = _writes.then((_) async {
      try {
        await _preferences?.setStringList(_historyKey, snapshot);
      } catch (_) {
        // 保留内存历史，下次连接时写入完整快照。
      }
    });
  }
}
