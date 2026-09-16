import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/settings/app_settings_controller.dart';
import '../providers/app_providers.dart';
import 'device_connection_notification_service.dart';
import 'mac_notification_bridge.dart';
import 'notification_database.dart';
import 'notification_forwarding_client.dart';
import 'notification_forwarding_service.dart';
import 'notification_models.dart';

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

      // 服务始终等待同一个真实数据库 Future，避免初始化期间写入临时库或重建会话。
      final databaseFuture = ref.read(notificationDatabaseProvider.future);

      final service = NotificationForwardingService(
        client: client,
        databaseFuture: databaseFuture,
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
        appIconPathResolver: (deviceId, packageName) {
          final packages = ref.read(packagesProvider(deviceId)).value;
          if (packages != null) {
            for (final p in packages) {
              if (p.name == packageName) return p.iconLocalPath;
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
      }, fireImmediately: true);

      ref.onDispose(service.dispose);
      return service;
    });

/// 转发会话状态变化流，供当前消息页展示重连与队列缺口状态。
final notificationForwardingStateChangesProvider = StreamProvider<String>((ref) {
  return ref.watch(notificationForwardingServiceProvider).stateChanges;
});

/// 消息入库或移除事件流，消息列表按 Companion 来源选择性刷新。
final notificationMessageChangesProvider =
    StreamProvider<NotificationStoreChange>((ref) {
      return ref.watch(notificationForwardingServiceProvider).messageChanges;
    });

/// 设备连接状态与桌面通知监听服务 Provider。
final deviceConnectionNotificationServiceProvider =
    Provider<DeviceConnectionNotificationService>((ref) {
      final bridge = ref.watch(macNotificationBridgeProvider);
      final service = DeviceConnectionNotificationService(
        bridge: bridge,
        settingsGetter: () => ref.read(appSettingsProvider),
        bodyTextResolver: () {
          final locale = ref.read(appSettingsProvider).language.locale;
          return AppLocalizations(locale).t('deviceConnected');
        },
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
      }, fireImmediately: true);

      ref.onDispose(service.dispose);
      return service;
    });
