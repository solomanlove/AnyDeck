import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../adb/discovered_device.dart';
import '../../emulator/android_emulator.dart';
import '../../emulator/emulator_connection.dart';
import 'device_registry_storage.dart';

typedef _Connection = ({
  String name,
  String id,
  DateTime? connectedAt,
  DateTime? disconnectedAt,
});
typedef _Transport = ({String? transportId, String status});

/// 保存 Android AVD 连接历史和已确认的 HarmonyOS 模拟器端点。
class DeviceRegistryEmulators {
  static const _historyKey = 'devices.emulatorConnections.v1';
  static const _harmonyHistoryKey = 'devices.harmonyEmulators.v1';
  final _history = <_Connection>[];
  final _harmonyIds = <String>{};
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
    _harmonyIds.addAll(prefs.getStringList(_harmonyHistoryKey) ?? const []);
    for (final entry in prefs.getStringList(_historyKey) ?? const <String>[]) {
      try {
        final fields = jsonDecode(entry);
        if (fields is! List || fields.length < 2 || fields.length > 4) continue;
        final name = fields[0];
        final id = fields[1];
        if (name is String &&
            id is String &&
            EmulatorConnectionService.isAvdName(name) &&
            EmulatorConnectionService.isTransport(id)) {
          final start = _parseTime(fields.elementAtOrNull(2));
          final end = _parseTime(fields.elementAtOrNull(3));
          _history.add((
            name: name,
            id: id,
            connectedAt: start,
            disconnectedAt: end != null && start != null && end.isBefore(start)
                ? null
                : end,
          ));
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
        final match = RegExp(r'^sdk_gphone(16k|64)_(arm64|x86_64)$')
            .firstMatch(product ?? '');
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

  static DateTime? _parseTime(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  /// 离线沿用已确认记录；在线端点只使用本次探测，防止端口复用时误标。
  Set<String> syncHarmonyIds(
    List<DiscoveredDevice> devices,
    Map<String, bool?> probes,
  ) {
    final visible = {..._harmonyIds};
    var changed = false;
    for (final device in devices) {
      final confirmed = device.isHarmony ? probes[device.id] : false;
      if (confirmed == true) {
        visible.add(device.id);
      } else {
        visible.remove(device.id);
      }
      if (confirmed == null || _preferences == null) continue;
      final updated = confirmed
          ? _harmonyIds.add(device.id)
          : _harmonyIds.remove(device.id);
      changed = changed || updated;
    }
    if (changed) unawaited(_saveHarmonyIds());
    return visible;
  }

  /// 每个 transport 代次只探测一次；连接变化时结束旧会话并忽略迟到的查询。
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
    final observedAt = DateTime.now().toUtc();
    var endedConnection = false;
    for (final entry in _transports.entries) {
      final id = entry.key;
      if (current[id] == entry.value) continue;
      final name = _confirmed.remove(id);
      _queries.remove(id);
      if (entry.value.status == 'device' &&
          name != null &&
          _endConnection(name, id, observedAt)) {
        endedConnection = true;
      }
    }
    if (endedConnection) unawaited(_save());
    for (final device in devices) {
      final transport = current[device.id];
      if (transport == null || transport == _transports[device.id]) continue;
      final token = Object();
      _queries[device.id] = token;
      unawaited(
        _identify(
          connection,
          device,
          token,
          onChanged,
          isActive,
          device.isOnline ? observedAt : null,
        ),
      );
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
    DateTime? connectedAt,
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
    final previousIndex = _connectionIndex(name, device.id);
    final previous = previousIndex == -1
        ? null
        : _history.removeAt(previousIndex);
    _history.add((
      name: name,
      id: device.id,
      // 使用发现快照的时间，排除 AVD 身份查询耗时。
      connectedAt: connectedAt ?? previous?.connectedAt,
      disconnectedAt: connectedAt == null ? previous?.disconnectedAt : null,
    ));
    unawaited(_save());
    onChanged(device.id, previousName, name);
  }

  int _connectionIndex(String name, String id) =>
      _history.lastIndexWhere((entry) => entry.name == name && entry.id == id);

  bool _endConnection(String name, String id, DateTime time) {
    final index = _connectionIndex(name, id);
    if (index == -1) return false;
    final entry = _history[index];
    final start = entry.connectedAt;
    if (start == null || entry.disconnectedAt != null) return false;

    // 系统时间向后调整时，时长最低为零。
    _history[index] = (
      name: name,
      id: id,
      connectedAt: start,
      disconnectedAt: time.isBefore(start) ? start : time,
    );
    return true;
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

  /// 只有当前探测、已持久化的端口归属和由确认记录生成的稳定键可作为启动依据。
  bool isConfirmed(String id, String name) => _transports.containsKey(id)
      ? _confirmed[id] == name
      : id == keyFor(name) || _connectionIndex(name, id) != -1;

  /// 每个 AVD 按最近上线时间列出曾用端口，旧端口保留原有顺序。
  Map<String, List<EmulatorConnectionHistoryEntry>> get historyByName {
    final result = <String, Map<String, EmulatorConnectionHistoryEntry>>{};
    for (final entry in _legacy.entries) {
      result.putIfAbsent(entry.value, () => {})[entry.key] = (
        id: entry.key,
        connectedAt: null,
        disconnectedAt: null,
      );
    }
    for (final entry in _history) {
      result.putIfAbsent(entry.name, () => {})[entry.id] = (
        id: entry.id,
        connectedAt: entry.connectedAt,
        disconnectedAt: entry.disconnectedAt,
      );
    }
    return result.map((name, ports) {
      final ordered = ports.values.indexed.toList()
        ..sort((left, right) {
          final leftTime = left.$2.connectedAt;
          final rightTime = right.$2.connectedAt;
          if (leftTime != null && rightTime == null) return 1;
          if (leftTime == null && rightTime != null) return -1;
          final order = leftTime?.compareTo(rightTime!) ?? 0;
          return order == 0 ? left.$1.compareTo(right.$1) : order;
        });
      return MapEntry(name, List.unmodifiable(ordered.map((item) => item.$2)));
    });
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
    var harmonyChanged = false;
    for (final id in ids) {
      if (_harmonyIds.remove(id)) harmonyChanged = true;
      _confirmed.remove(id);
      _queries.remove(id);
      _transports.remove(id);
    }
    if (_history.length != previous) await _save();
    if (harmonyChanged) await _saveHarmonyIds();
  }

  Future<void> _saveHarmonyIds() {
    final snapshot = _harmonyIds.toList();
    return _writes = _writes.then((_) async {
      try {
        await _preferences?.setStringList(_harmonyHistoryKey, snapshot);
      } catch (_) {
        // 当前会话仍保留已确认的标识。
      }
    });
  }

  Future<void> _save() {
    final snapshot = [
      for (final entry in _history)
        jsonEncode([
          entry.name,
          entry.id,
          if (entry.connectedAt != null || entry.disconnectedAt != null)
            entry.connectedAt?.toIso8601String(),
          if (entry.disconnectedAt != null)
            entry.disconnectedAt!.toIso8601String(),
        ]),
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
