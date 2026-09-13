import 'package:any_deck/core/notifications/device_connection_notification_service.dart';
import 'package:any_deck/core/notifications/mac_notification_bridge.dart';
import 'package:any_deck/core/notifications/notification_models.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMacNotificationBridge extends MacNotificationBridge {
  _FakeMacNotificationBridge() : super();

  final List<Map<String, dynamic>> sentNotifications = [];
  final List<String> removedNotificationIds = [];

  @override
  Future<bool> showNotification({
    required String id,
    required String title,
    String body = '',
    Map<String, dynamic>? payload,
  }) async {
    sentNotifications.add({
      'id': id,
      'title': title,
      'body': body,
      'payload': payload,
    });
    return true;
  }

  @override
  Future<void> removeNotification(String id) async {
    removedNotificationIds.add(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Notification Models & Parsing', () {
    test('NotificationEvent parses successfully from JSON', () {
      final json = {
        'event': 'posted',
        'key': '0|com.tencent.mm|1|null|10001',
        'packageName': 'com.tencent.mm',
        'title': 'Test Sender',
        'content': 'Hello World',
        'postTime': 1700000000000,
        'sequence': 101,
      };

      final event = NotificationEvent.fromJson(json);
      expect(event.event, equals('posted'));
      expect(event.key, equals('0|com.tencent.mm|1|null|10001'));
      expect(event.packageName, equals('com.tencent.mm'));
      expect(event.title, equals('Test Sender'));
      expect(event.content, equals('Hello World'));
      expect(event.postTime.millisecondsSinceEpoch, equals(1700000000000));
      expect(event.sequence, equals(101));
    });

    test('NotificationSessionStatus parses and computes readiness', () {
      const readyStatus = NotificationSessionStatus(
        isSharingEnabled: true,
        isPermissionGranted: true,
        installationId: 'inst_abc',
        androidUserId: 0,
        rawStatus: 'ok',
      );
      expect(readyStatus.isReady, isTrue);

      const notGrantedStatus = NotificationSessionStatus(
        isSharingEnabled: true,
        isPermissionGranted: false,
        installationId: 'inst_abc',
        androidUserId: 0,
        rawStatus: 'ok',
      );
      expect(notGrantedStatus.isReady, isFalse);
    });
  });

  group('DeviceConnectionNotificationService', () {
    test('deduplicates connection events for the same serial', () async {
      final fakeBridge = _FakeMacNotificationBridge();
      final service = DeviceConnectionNotificationService(
        bridge: fakeBridge,
        settingsGetter: () => const AppSettings(deviceConnectNotification: true),
        bodyTextResolver: () => '设备已连接',
        connectDebounce: const Duration(milliseconds: 50),
        disconnectDebounce: const Duration(milliseconds: 50),
      );

      final snapshot = DeviceConnectionSnapshot(
        id: '192.168.1.50:5555',
        serial: 'SERIAL_XYZ',
        displayName: 'Pixel 8',
        isOnline: true,
        isAndroid: true,
      );

      // 第一次连接上线
      service.onDevicesUpdated([snapshot]);
      await Future.delayed(const Duration(milliseconds: 80));

      expect(fakeBridge.sentNotifications.length, equals(1));
      expect(fakeBridge.sentNotifications.first['title'], equals('Pixel 8'));

      // 相同的 serial 在网络波动或重复上报时不重复通知
      service.onDevicesUpdated([snapshot]);
      await Future.delayed(const Duration(milliseconds: 80));
      expect(fakeBridge.sentNotifications.length, equals(1));

      // 断开连接后重新连接应再次通知
      final offlineSnapshot = DeviceConnectionSnapshot(
        id: '192.168.1.50:5555',
        serial: 'SERIAL_XYZ',
        displayName: 'Pixel 8',
        isOnline: false,
        isAndroid: true,
      );
      service.onDevicesUpdated([offlineSnapshot]);
      await Future.delayed(const Duration(milliseconds: 80));

      service.onDevicesUpdated([snapshot]);
      await Future.delayed(const Duration(milliseconds: 80));
      expect(fakeBridge.sentNotifications.length, equals(2));

      service.dispose();
    });

    test('respects deviceConnectNotification setting', () async {
      final fakeBridge = _FakeMacNotificationBridge();
      final service = DeviceConnectionNotificationService(
        bridge: fakeBridge,
        settingsGetter: () => const AppSettings(deviceConnectNotification: false),
        bodyTextResolver: () => '设备已连接',
        connectDebounce: const Duration(milliseconds: 50),
        disconnectDebounce: const Duration(milliseconds: 50),
      );

      final snapshot = DeviceConnectionSnapshot(
        id: 'usb_1',
        serial: 'SERIAL_ABC',
        displayName: 'Xiaomi 14',
        isOnline: true,
        isAndroid: true,
      );

      service.onDevicesUpdated([snapshot]);
      await Future.delayed(const Duration(milliseconds: 80));

      expect(fakeBridge.sentNotifications.isEmpty, isTrue);
      service.dispose();
    });
  });
}
