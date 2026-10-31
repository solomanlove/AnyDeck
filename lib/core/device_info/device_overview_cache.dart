import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'device_overview.dart';

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

  Future<void> clear(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$deviceId');
    } catch (_) {
      // 缓存清理错误不打断设备操作。
    }
  }
}
