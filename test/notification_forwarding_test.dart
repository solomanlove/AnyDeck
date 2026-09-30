import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/notifications/device_connection_notification_service.dart';
import 'package:any_deck/core/notifications/mac_notification_bridge.dart';
import 'package:any_deck/core/notifications/notification_database.dart';
import 'package:any_deck/core/notifications/notification_forwarding_client.dart';
import 'package:any_deck/core/notifications/notification_forwarding_service.dart';
import 'package:any_deck/core/notifications/notification_models.dart';
import 'package:any_deck/core/notifications/notification_device_identity.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeMacNotificationBridge extends MacNotificationBridge {
  _FakeMacNotificationBridge() : super();

  final List<Map<String, dynamic>> sentNotifications = [];
  final List<String> removedNotificationIds = [];
  String authorizationStatus = 'authorized';
  bool authorizationResult = true;
  int authorizationRequestCount = 0;

  @override
  Future<String> getAuthorizationStatus() async => authorizationStatus;

  @override
  Future<bool> requestAuthorization() async {
    authorizationRequestCount++;
    if (authorizationResult) {
      authorizationStatus = 'authorized';
    }
    return authorizationResult;
  }

  @override
  Future<bool> showNotification({
    required String id,
    required String title,
    String body = '',
    String subtitle = '',
    String? iconPath,
    Map<String, dynamic>? payload,
  }) async {
    sentNotifications.add({
      'id': id,
      'title': title,
      'body': body,
      'subtitle': subtitle,
      'iconPath': iconPath,
      'payload': payload,
    });
    return true;
  }

  @override
  Future<void> removeNotification(String id) async {
    removedNotificationIds.add(id);
  }
}

class _FakeNotificationForwardingClient extends NotificationForwardingClient {
  _FakeNotificationForwardingClient({this.multipleDevices = false})
    : super(AdbService(executable: 'unused-in-test'));

  final bool multipleDevices;

  @override
  Future<int> getCurrentUser(String deviceId) async => 10;

  @override
  Future<NotificationSessionStatus> getStatus(
    String deviceId,
    int userId,
  ) async {
    return NotificationSessionStatus(
      isSharingEnabled: true,
      isPermissionGranted: true,
      installationId: multipleDevices
          ? 'installation_$deviceId'
          : 'installation_forwarding',
      androidUserId: 10,
      rawStatus: 'ok',
    );
  }

  @override
  Future<String> startSession(String deviceId, int userId) async => 'session_1';

  @override
  Future<Map<String, dynamic>> poll(
    String deviceId,
    int userId,
    String sessionId,
    int cursor,
  ) async {
    return {
      'status': 'ok',
      'nextCursor': 1,
      'gap': true,
      'events': [
        {
          'event': 'posted',
          'key': 'message_key',
          'packageName': 'com.example.chat',
          'title': 'Alice',
          'content': 'Hello',
          'postTime': 1700000000000,
          'sequence': 1,
        },
      ],
    };
  }

  @override
  Future<void> stopSession(
    String deviceId,
    int userId,
    String sessionId,
  ) async {}
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
      expect(
        fakeBridge.sentNotifications.first['payload'],
        containsPair('deviceSerial', 'SERIAL_XYZ'),
      );

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

    test(
      'requests macOS authorization before first connection notice',
      () async {
        final fakeBridge = _FakeMacNotificationBridge()
          ..authorizationStatus = 'notDetermined';
        final service = DeviceConnectionNotificationService(
          bridge: fakeBridge,
          settingsGetter: () =>
              const AppSettings(deviceConnectNotification: true),
          bodyTextResolver: () => '设备已连接',
          connectDebounce: const Duration(milliseconds: 50),
          disconnectDebounce: const Duration(milliseconds: 50),
        );

        service.onDevicesUpdated([
          const DeviceConnectionSnapshot(
            id: 'usb_2',
            serial: 'SERIAL_PERMISSION',
            displayName: 'Pixel 9',
            isOnline: true,
            isAndroid: true,
          ),
        ]);
        await Future.delayed(const Duration(milliseconds: 80));

        expect(fakeBridge.authorizationRequestCount, equals(1));
        expect(fakeBridge.sentNotifications.length, equals(1));
        service.dispose();
      },
    );
  });

  test(
    'forwarding persists source, publishes refresh, and sends navigable payload',
    () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = await Directory.systemTemp.createTemp('forwarding_test_');
      final database = NotificationDatabase(
        '${tempDir.path}/notifications.sqlite',
      );
      final databaseCompleter = Completer<NotificationDatabase>();
      final bridge = _FakeMacNotificationBridge();
      final service = NotificationForwardingService(
        client: _FakeNotificationForwardingClient(),
        databaseFuture: databaseCompleter.future,
        bridge: bridge,
        settingsGetter: () => const AppSettings(),
        appNameResolver: (_, _) => 'Example Chat',
        appIconPathResolver: (_, _) => '/cached/example_chat.png',
        deviceIdentityResolver: (_, serial, _) => NotificationDeviceIdentity(
          stableId: serial,
          name: '工作手机',
        ),
        deviceLabelResolver: (identity) => identity.label([]),
      );
      addTearDown(() {
        service.dispose();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final changeFuture = service.messageChanges.first.timeout(
        const Duration(seconds: 2),
      );

      service.startForwarding(
        const AdbDevice(id: 'usb_route', status: 'device'),
        'SERIAL_FORWARDING',
      );
      await Future.delayed(const Duration(milliseconds: 20));
      expect(bridge.sentNotifications, isEmpty);

      databaseCompleter.complete(database);
      final change = await changeFuture;

      expect(change.installationId, equals('installation_forwarding'));
      expect(change.androidUserId, equals(10));
      expect(service.hasQueueGap('usb_route'), isTrue);
      expect(bridge.sentNotifications, hasLength(1));
      expect(
        bridge.sentNotifications.single['iconPath'],
        equals('/cached/example_chat.png'),
      );
      expect(
        bridge.sentNotifications.single['id'],
        equals('notif_installation_forwarding_10_message_key'),
      );
      expect(
        bridge.sentNotifications.single['payload'],
        containsPair('targetTab', 15),
      );
      expect(
        bridge.sentNotifications.single['payload'],
        containsPair('notificationKey', 'message_key'),
      );
      expect(
        bridge.sentNotifications.single['payload'],
        containsPair('deviceSerial', 'SERIAL_FORWARDING'),
      );

      final source = await database.resolveSource('SERIAL_FORWARDING');
      expect(source?.installationId, equals('installation_forwarding'));
      expect(source?.identity?.name, '工作手机');
      expect(
        bridge.sentNotifications.single['title'],
        '工作手机 · DING · Example Chat',
      );
      expect(bridge.sentNotifications.single['subtitle'], 'Alice');
      expect(bridge.sentNotifications.single['body'], 'Hello');
      expect(
        bridge.sentNotifications.single['payload'],
        containsPair('installationId', 'installation_forwarding'),
      );
      expect(
        bridge.sentNotifications.single['payload'],
        containsPair('androidUserId', 10),
      );
      expect(
        await database.queryMessages('installation_forwarding', 10),
        hasLength(1),
      );
    },
  );

  test('two phones keep identical notifications separate with body preview disabled', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('multi_phone_');
    final database = NotificationDatabase(
      '${directory.path}/notifications.sqlite',
    );
    // 与生产 Provider 一致，先完成数据库初始化再启动并行会话。
    await database.pruneExpired();
    final bridge = _FakeMacNotificationBridge();
    final service = NotificationForwardingService(
      client: _FakeNotificationForwardingClient(multipleDevices: true),
      databaseFuture: Future.value(database),
      bridge: bridge,
      settingsGetter: () => const AppSettings(notificationBodyPreview: false),
      appNameResolver: (_, _) => '微信',
      appIconPathResolver: (_, _) => null,
      deviceIdentityResolver: (_, serial, _) =>
          NotificationDeviceIdentity(stableId: serial, name: 'Pixel'),
      deviceLabelResolver: (identity) =>
          identity.label(['SERIAL_A1234', 'SERIAL_B1234']),
    );
    final received = service.messageChanges.take(2).toList();
    try {
      service.startForwarding(
        const AdbDevice(id: 'phone_a', status: 'device'),
        'SERIAL_A1234',
      );
      service.startForwarding(
        const AdbDevice(id: 'phone_b', status: 'device'),
        'SERIAL_B1234',
      );
      await received.timeout(const Duration(seconds: 5));
      final notices = bridge.sentNotifications;
      expect(notices.map((n) => n['title']).toSet(), {
        'Pixel · A1234 · 微信',
        'Pixel · B1234 · 微信',
      });
      expect(notices.map((n) => n['id']).toSet(), hasLength(2));
      expect(
        notices.every((n) => n['body'] == '' && n['subtitle'] == 'Alice'),
        isTrue,
      );
      final a = await database.queryMessages('installation_phone_a', 10);
      final b = await database.queryMessages('installation_phone_b', 10);
      expect(a, hasLength(1));
      expect(b, hasLength(1));
      expect(a.single.id, isNot(b.single.id));
      await database.clearMessages('installation_phone_a', 10);
      expect(
        await database.queryMessages('installation_phone_b', 10),
        hasLength(1),
      );
    } finally {
      service.dispose();
      await directory.delete(recursive: true);
    }
  });
}
