import 'dart:async';
import '../../app/settings/app_settings.dart';
import 'mac_notification_bridge.dart';

/// 简化表示设备连接状态的不可变对象。
class DeviceConnectionSnapshot {
  const DeviceConnectionSnapshot({
    required this.id,
    required this.serial,
    required this.displayName,
    required this.isOnline,
    required this.isAndroid,
  });

  final String id;
  final String serial;
  final String displayName;
  final bool isOnline;
  final bool isAndroid;
}

/// 负责 Android 设备连接检测、物理 serial 合并、2 秒防抖与系统通知分发。
class DeviceConnectionNotificationService {
  DeviceConnectionNotificationService({
    required this.bridge,
    required this.settingsGetter,
    required this.bodyTextResolver,
    this.connectDebounce = const Duration(seconds: 2),
    this.disconnectDebounce = const Duration(seconds: 2),
  });

  final MacNotificationBridge bridge;
  final AppSettings Function() settingsGetter;
  final String Function() bodyTextResolver;
  final Duration connectDebounce;
  final Duration disconnectDebounce;

  final Set<String> _notifiedSerials = {};
  final Map<String, Timer> _connectTimers = {};
  final Map<String, Timer> _disconnectTimers = {};

  /// 当设备列表或状态更新时调用。
  void onDevicesUpdated(List<DeviceConnectionSnapshot> devices) {
    final onlineAndroidMap = <String, DeviceConnectionSnapshot>{};

    for (final d in devices) {
      if (d.isAndroid && d.isOnline) {
        final key = d.serial.isNotEmpty ? d.serial : d.id;
        // 同一物理 serial 合并，保留已存在或具名对象
        onlineAndroidMap.putIfAbsent(key, () => d);
      }
    }

    // 1. 处理上线事件（2 秒防抖）
    for (final entry in onlineAndroidMap.entries) {
      final serial = entry.key;
      final device = entry.value;

      // 如果正在等待断线确认，取消断线计时
      _disconnectTimers.remove(serial)?.cancel();

      if (_notifiedSerials.contains(serial)) {
        // 已通知过，跳过
        continue;
      }

      if (_connectTimers.containsKey(serial)) {
        // 已经在 2 秒防抖倒计时中
        continue;
      }

      // 启动连接防抖
      _connectTimers[serial] = Timer(connectDebounce, () async {
        _connectTimers.remove(serial);
        final settings = settingsGetter();
        if (!settings.deviceConnectNotification) {
          _notifiedSerials.add(serial);
          return;
        }

        final title = device.displayName.isNotEmpty
            ? device.displayName
            : (device.serial.isNotEmpty ? device.serial : device.id);
        final body = bodyTextResolver();

        await bridge.showNotification(
          id: 'conn_$serial',
          title: title,
          body: body,
          payload: {
            'type': 'device_connected',
            'deviceId': device.id,
            'targetTab': 0,
          },
        );
        _notifiedSerials.add(serial);
      });
    }

    // 2. 处理离线事件（防抖后重置已通知状态）
    final currentOnlineKeys = onlineAndroidMap.keys.toSet();
    final disconnectedKeys = _notifiedSerials.difference(currentOnlineKeys);

    for (final serial in disconnectedKeys) {
      if (_disconnectTimers.containsKey(serial)) continue;

      _disconnectTimers[serial] = Timer(disconnectDebounce, () {
        _disconnectTimers.remove(serial);
        _notifiedSerials.remove(serial);
      });
    }

    // 清理未完成但已离线的上线 Timer
    final pendingKeys = _connectTimers.keys.toList();
    for (final key in pendingKeys) {
      if (!currentOnlineKeys.contains(key)) {
        _connectTimers.remove(key)?.cancel();
      }
    }
  }

  void dispose() {
    for (final t in _connectTimers.values) {
      t.cancel();
    }
    _connectTimers.clear();
    for (final t in _disconnectTimers.values) {
      t.cancel();
    }
    _disconnectTimers.clear();
    _notifiedSerials.clear();
  }
}
