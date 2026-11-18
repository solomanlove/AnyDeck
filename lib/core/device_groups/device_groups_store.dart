import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'device_group.dart';

/// 主窗口设备管理专属存储；单个 JSON 保存分组及成员，避免部分写入。
class DeviceGroupsStore {
  static const key = 'devices.groups.v1';

  Future<DeviceGroupsState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return DeviceGroupsState();
    return DeviceGroupsState.fromJson(jsonDecode(raw));
  }

  Future<void> save(DeviceGroupsState value) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(key, jsonEncode(value.toJson()));
    if (!saved) throw StateError('Device groups could not be saved');
  }
}
