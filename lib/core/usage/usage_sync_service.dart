import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../adb/adb_service.dart';
import '../apps/app_management_service.dart';
import 'usage_snapshot.dart';

/// 复用 AdbService 和安装能力，按需读取当前 Android 用户的快照。
class UsageSyncService {
  UsageSyncService(this.adb, this.apps);

  static const packageName = 'com.adbmanage.companion';
  static const apkAsset = 'assets/android/usage_companion.apk';
  final AdbService adb;
  final AppManagementService apps;

  Future<int> _currentUser(String deviceId) async {
    final result = await adb.shellArgs(deviceId, ['am', 'get-current-user']);
    final user = int.tryParse(result.stdout.trim());
    if (!result.isSuccess || user == null || user < 0) {
      throw const UsageSyncException('usageConnectionFailed');
    }
    return user;
  }

  Future<UsageSnapshot> sync(String deviceId) async {
    final user = await _currentUser(deviceId);
    final installed = await adb.shellArgs(deviceId, [
      'pm',
      'path',
      '--user',
      '$user',
      packageName,
    ]);
    if (!installed.isSuccess || !installed.stdout.contains('package:')) {
      throw const UsageSyncException('usageCompanionMissing');
    }
    final result = await adb.shellArgs(deviceId, [
      'content',
      'call',
      '--user',
      '$user',
      '--uri',
      'content://$packageName.usage',
      '--method',
      'snapshot',
    ]);
    if (!result.isSuccess) {
      throw const UsageSyncException('usageConnectionFailed');
    }
    final snapshot = UsageSnapshot.fromAdbOutput(result.stdout);
    if (snapshot.androidUserId != user ||
        await _currentUser(deviceId) != user) {
      throw const UsageSyncException('usageUserChanged');
    }
    return snapshot;
  }

  /// 安装复用现有 AppManagementService，临时 APK 无论成功失败均删除。
  Future<void> install(String deviceId) async {
    final directory = await Directory.systemTemp.createTemp('anydeck_usage_');
    try {
      final data = await rootBundle.load(apkAsset);
      final file = File('${directory.path}/companion.apk');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final result = await apps.installApk(deviceId, file.path);
      if (!result.isSuccess) {
        throw const UsageSyncException('usageInstallFailed');
      }
      await openCompanion(deviceId);
    } finally {
      await directory.delete(recursive: true);
    }
  }

  Future<void> openCompanion(String deviceId) async {
    final user = await _currentUser(deviceId);
    final result = await adb.shellArgs(deviceId, [
      'am',
      'start',
      '--user',
      '$user',
      '-n',
      '$packageName/.MainActivity',
    ]);
    if (!result.isSuccess ||
        result.stdout.contains('Error') ||
        result.stderr.contains('Error')) {
      throw const UsageSyncException('usageCompanionMissing');
    }
  }
}

/// 最小版仅缓存每个 ADB 路由最后一份快照，不建立长期历史或重复累计。
class UsageSnapshotCache {
  String _key(String deviceId) => 'usage.snapshot.v1.$deviceId';

  Future<UsageSnapshot?> load(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_key(deviceId));
    if (raw == null) return null;
    try {
      return UsageSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String deviceId, UsageSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key(deviceId), jsonEncode(snapshot.json))) {
      throw const UsageSyncException('usageSaveFailed');
    }
  }

  Future<void> clear(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_key(deviceId))) {
      throw const UsageSyncException('usageSaveFailed');
    }
  }
}
