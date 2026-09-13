import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings/app_settings_controller.dart';
import '../providers/app_providers.dart';
import 'device_connection_notification_service.dart';
import 'mac_notification_bridge.dart';
import 'notification_database.dart';
import 'notification_forwarding_client.dart';
import 'notification_forwarding_service.dart';

/// 全局 macOS 本地通知桥接单例 Provider。
final macNotificationBridgeProvider = Provider<MacNotificationBridge>((ref) {
  final bridge = MacNotificationBridge();
  ref.onDispose(bridge.dispose);
  return bridge;
});

/// 全局本地消息持久化 SQLite 数据库 Provider。
final notificationDatabaseProvider =
    FutureProvider<NotificationDatabase>((ref) async {
      final db = await NotificationDatabase.openDefault();
      // 启动时自动清理过期历史
      await db.pruneExpired();
      return db;
    });

/// 手机端 Companion ADB 通信 Client。
final notificationForwardingClientProvider =
    Provider<NotificationForwardingClient>((ref) {
      return NotificationForwardingClient(ref.watch(adbServiceProvider));
    });

/// 全局消息转发调度服务 Provider。
final notificationForwardingServiceProvider =
    Provider<NotificationForwardingService>((ref) {
      final client = ref.watch(notificationForwardingClientProvider);
      final bridge = ref.watch(macNotificationBridgeProvider);

      // 同步获取数据库，若尚未就绪则返回轻量内存数据库路径兜底
      final dbAsync = ref.watch(notificationDatabaseProvider);
      final database = dbAsync.value ?? const NotificationDatabase('');

      final service = NotificationForwardingService(
        client: client,
        database: database,
        bridge: bridge,
        settingsGetter: () => ref.read(appSettingsProvider),
        appNameResolver: (deviceId, packageName) {
          final packages = ref.read(packagesProvider(deviceId)).value;
          if (packages != null) {
            for (final p in packages) {
              if (p.name == packageName &&
                  p.label != null &&
                  p.label!.isNotEmpty) {
                return p.label;
              }
            }
          }
          return null;
        },
      );

      // 监听已连接设备列表变化，对开启转发的在线设备启动会话，对离线设备停止会话
      ref.listen<List<RegisteredDevice>>(deviceRegistryProvider, (_, next) async {
        final onlineAndroidMap = <String, RegisteredDevice>{};
        for (final d in next) {
          if (d.isOnline && d.status == 'device' && !d.isIos && !d.isHarmony) {
            onlineAndroidMap[d.id] = d;
            final serial =
                (d.serial?.isNotEmpty == true) ? d.serial! : d.id;
            final enabled = await service.isForwardingEnabled(serial);
            if (enabled && !service.isForwardingActive(d.id)) {
              service.startForwarding(d.toAdbDevice, serial);
            }
          }
        }
        for (final activeId in service.activeSessionDeviceIds) {
          if (!onlineAndroidMap.containsKey(activeId)) {
            service.stopForwarding(activeId);
          }
        }
      });

      ref.onDispose(service.dispose);
      return service;
    });

/// 设备连接状态与桌面通知监听服务 Provider。
final deviceConnectionNotificationServiceProvider =
    Provider<DeviceConnectionNotificationService>((ref) {
      final bridge = ref.watch(macNotificationBridgeProvider);
      final service = DeviceConnectionNotificationService(
        bridge: bridge,
        settingsGetter: () => ref.read(appSettingsProvider),
        bodyTextResolver: () => '设备已连接',
      );

      // 订阅注册表设备列表变化
      ref.listen<List<RegisteredDevice>>(deviceRegistryProvider, (_, next) {
        final snapshots = next.map((d) {
          final serial =
              (d.serial?.isNotEmpty == true) ? d.serial! : d.id;
          final displayName = (d.customName?.isNotEmpty == true)
              ? d.customName!
              : (d.model ?? d.id);
          return DeviceConnectionSnapshot(
            id: d.id,
            serial: serial,
            displayName: displayName,
            isOnline: d.isOnline && d.status == 'device',
            isAndroid: !d.isIos && !d.isHarmony,
          );
        }).toList();
        service.onDevicesUpdated(snapshots);
      });

      ref.onDispose(service.dispose);
      return service;
    });
