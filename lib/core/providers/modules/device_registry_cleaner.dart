import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/files/controller/file_favorite_folders_controller.dart';
import '../../notifications/notification_database.dart';
import '../../usage/companion_database.dart';
import 'service_providers.dart';

/// 设备关联缓存与数据库彻底清理服务。
///
/// 当设备被删除时，负责级联清理该设备在本机与设备端留下的所有痕迹：
/// 1. 设备硬件概览信息缓存（SharedPreferences）；
/// 2. 应用列表与本机图标缓存目录、传输临时分片及设备端 DEX/临时目录；
/// 3. 文件管理中针对该设备保存的常用收藏文件夹（SharedPreferences）；
/// 4. Companion 历史使用统计 SQLite 数据库（routes/records/cursors）；
/// 5. 手机通知转发历史 SQLite 数据库（notification_sources/notifications）。
class DeviceRegistryCleaner {
  /// 彻底清理指定设备标识符（物理序列号或网络连接 ID）的所有关联缓存与数据记录。
  static Future<void> cleanupAll(Ref ref, String deviceId) async {
    if (deviceId.isEmpty) return;

    // 1. 清理设备概览本地缓存
    try {
      await ref.read(deviceInfoServiceProvider).clearDeviceCache(deviceId);
    } catch (_) {
      // 容错处理：不阻断主清理链路
    }

    // 2. 清理应用包列表缓存、本机图标目录与远程临时目录
    try {
      await ref.read(appManagementServiceProvider).clearDeviceCache(deviceId);
    } catch (_) {
      // 容错处理
    }

    // 3. 清除文件管理中针对该设备保存的常用收藏文件夹
    try {
      await ref.read(fileFavoriteFoldersProvider.notifier).clearDevice(deviceId);
    } catch (_) {
      // 容错处理
    }

    // 4. 清理 Companion 历史统计 SQLite 数据库
    try {
      final companionDb = await CompanionDatabase.openDefault();
      await companionDb.clear(deviceId);
    } catch (_) {
      // 容错处理
    }

    // 5. 清理通知转发记录与关联源 SQLite 数据库
    try {
      final notifDb = await NotificationDatabase.openDefault();
      await notifDb.clearSource(deviceId);
    } catch (_) {
      // 容错处理
    }
  }
}
