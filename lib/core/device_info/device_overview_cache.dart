import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'device_overview.dart';

/// 可跨连接通道复用的展示字段。
typedef DeviceDisplayIdentity = ({
  String? name,
  String? brand,
  String? manufacturer,
});

/// 概览与真实采集时间；旧缓存时间未知，不能用读取时间替代。
class DeviceOverviewSnapshot {
  const DeviceOverviewSnapshot(this.overview, this.collectedAt);
  final DeviceOverview overview;
  final DateTime? collectedAt;
}

/// 保留原缓存键和扁平字段，附加可选时间以兼容已有 UI 与历史缓存。
class DeviceOverviewCache {
  static const _prefix = 'devices.overview.';

  Future<void> save(
    String deviceId,
    DeviceOverview overview, {
    DateTime? collectedAt,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefix$deviceId',
        jsonEncode({
          ...overview.toJson(),
          'collectedAt': collectedAt?.toUtc().toIso8601String(),
        }),
      );
    } catch (_) {
      // 本地缓存失败不影响实时查询。
    }
  }

  Future<DeviceOverviewSnapshot?> load(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$deviceId');
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return DeviceOverviewSnapshot(
        DeviceOverview.fromJson(json),
        DateTime.tryParse(json['collectedAt']?.toString() ?? '')?.toUtc(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 按硬件序列号读取旧版概览中的商品名与品牌，优先使用序列号对应的记录。
  Future<DeviceDisplayIdentity> loadDisplayIdentity(String serial) async {
    const empty = (name: null, brand: null, manufacturer: null);
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return empty;
    }
    final serialKey = '$_prefix$serial';
    var identity = _readDisplayIdentity(prefs.get(serialKey), serial) ?? empty;
    if (_hasCompleteIdentity(identity)) return identity;

    // 旧缓存也可能只有网络通道记录，必须匹配记录内的硬件序列号。
    final otherKeys =
        prefs
            .getKeys()
            .where((key) => key != serialKey && key.startsWith(_prefix))
            .toList()
          ..sort();
    for (final key in otherKeys) {
      final other = _readDisplayIdentity(prefs.get(key), serial);
      if (other == null) continue;
      identity = (
        name: identity.name ?? other.name,
        brand: identity.brand ?? other.brand,
        manufacturer: identity.manufacturer ?? other.manufacturer,
      );
      if (_hasCompleteIdentity(identity)) break;
    }
    return identity;
  }

  bool _hasCompleteIdentity(DeviceDisplayIdentity identity) =>
      identity.name != null &&
      identity.brand != null &&
      identity.manufacturer != null;

  DeviceDisplayIdentity? _readDisplayIdentity(Object? raw, String serial) {
    if (raw is! String) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> || json['serial'] != serial) {
        return null;
      }
      final name = _displayValue(json['name']);
      final model = _displayValue(json['model']);
      return (
        // 设备概览把原始型号当作商品名的兜底，避免它盖过其他通道的商品名。
        name: name == model || name == serial ? null : name,
        brand: _displayValue(json['brand']),
        manufacturer: _displayValue(json['manufacturer']),
      );
    } on FormatException {
      return null;
    }
  }

  String? _displayValue(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty || text == '-' || text.toLowerCase() == 'unknown'
        ? null
        : text;
  }

  Future<void> clear(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$deviceId');
    } catch (_) {
      // 缓存清理错误不打断设备操作。
    }
  }
}
