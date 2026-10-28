import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/nearby_share/harmony_share_notifications.dart';
import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/notifications/mac_notification_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client extends Fake implements ShareCoreClient {}

/// 使用实际 Dart MethodChannel 桥接与协调器，不启动 Core、App 或系统通知中心。
class _Service extends HarmonyShareService {
  _Service()
    : super.testing(
        client: _Client(),
        detectNetwork: () async =>
            throw StateError('Unexpected network access'),
        downloads: () async => throw StateError('Unexpected file access'),
      );
  void offer(int bytes) {
    pendingOffer = ShareIncomingOffer(InternetAddress.loopbackIPv4, bytes);
    notifyListeners();
  }

  void clearOffer() {
    pendingOffer = null;
    notifyListeners();
  }
}

Future<void> _turns() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/harmony_notification_permission');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Service service;
  late MacNotificationBridge bridge;
  HarmonyShareNotifications? notifications;
  final calls = <String>[];
  dynamic permission;
  dynamic delivery;
  var throws = false;
  var enabled = true;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    permission = 'authorized';
    delivery = true;
    throws = false;
    enabled = true;
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'getAuthorizationStatus') {
        if (throws) throw PlatformException(code: 'unavailable');
        return permission;
      }
      if (call.method == 'showNotification') return delivery;
      return true;
    });
    service = _Service();
    bridge = MacNotificationBridge(channel: channel);
    notifications = HarmonyShareNotifications(
      service: service,
      queue: service.sendQueue,
      bridge: bridge,
      enabled: () => enabled,
      text: (key) => key,
    );
  });
  tearDown(() {
    notifications?.dispose();
    service.dispose();
    bridge.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final failure in ['channel', 'missing', 'malformed']) {
    test('真实桥接权限查询 $failure 显示失败，后续授权可恢复', () async {
      throws = failure == 'channel';
      permission = failure == 'malformed' ? 'new_status' : null;
      service.offer(100);
      final original = service.pendingOffer;
      await _turns();
      expect(notifications!.deliveryFailed.value, isTrue);
      expect(service.pendingOffer, same(original));
      expect(calls, isNot(contains('showNotification')));
      expect(calls, isNot(contains('requestAuthorization')));

      throws = false;
      permission = 'authorized';
      service.offer(101);
      await _turns();
      expect(
        calls.where((method) => method == 'showNotification'),
        hasLength(1),
      );
      expect(notifications!.deliveryFailed.value, isFalse);
      expect(service.pendingOffer!.bytes, 101);
    });
  }
  for (final state in ['denied', 'notDetermined']) {
    test('明确权限状态 $state 不伪造桥接故障，也不后台申请权限', () async {
      permission = state;
      service.offer(100);
      await _turns();
      expect(notifications!.deliveryFailed.value, isFalse);
      expect(calls, isNot(contains('showNotification')));
      expect(calls, isNot(contains('requestAuthorization')));
      expect(service.pendingOffer, isNotNull);
    });
  }
  for (final dispose in [false, true]) {
    test('查询期间${dispose ? '销毁' : '停用'}不显示迟到故障或发送通知', () async {
      final waiting = Completer<String?>();
      permission = waiting.future;
      service.offer(100);
      await _turns();
      expect(calls, contains('getAuthorizationStatus'));
      if (dispose) {
        notifications!.dispose();
        notifications = null;
      } else {
        enabled = false;
      }
      waiting.complete(null);
      await _turns();
      if (!dispose) expect(notifications!.deliveryFailed.value, isFalse);
      expect(calls, isNot(contains('showNotification')));
      expect(calls, isNot(contains('requestAuthorization')));
    });
  }
  for (final action in ['disable', 'expire']) {
    test('送达回调返回失败前 $action，不覆盖当前健康状态', () async {
      final waiting = Completer<bool>();
      delivery = waiting.future;
      service.offer(100);
      await _turns();
      expect(calls, contains('showNotification'));
      if (action == 'disable') {
        enabled = false;
      } else {
        service.clearOffer();
      }
      waiting.complete(false);
      await _turns();
      expect(notifications!.deliveryFailed.value, isFalse);
      expect(calls, contains('removeNotification'));
    });
  }
  for (final stage in ['permission', 'delivery']) {
    for (final action in ['disable', 'expire', 'dispose']) {
      test('$stage 挂起期间 $action，超时与迟到完成不误报失败', () async {
        notifications!.dispose();
        notifications = HarmonyShareNotifications(
          service: service,
          queue: service.sendQueue,
          bridge: bridge,
          enabled: () => enabled,
          text: (key) => key,
          operationTimeout: const Duration(milliseconds: 20),
        );
        final query = Completer<String?>();
        final sent = Completer<bool>();
        if (stage == 'permission') {
          permission = query.future;
        } else {
          delivery = sent.future;
        }
        service.offer(100);
        await _turns();
        expect(
          calls,
          contains(
            stage == 'permission'
                ? 'getAuthorizationStatus'
                : 'showNotification',
          ),
        );
        if (action == 'dispose') {
          notifications!.dispose();
          notifications = null;
        } else if (action == 'disable') {
          enabled = false;
        } else {
          service.clearOffer();
        }
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (notifications != null) {
          expect(notifications!.deliveryFailed.value, isFalse);
        }
        query.complete(null);
        sent.complete(true);
        await _turns();
        if (notifications != null) {
          expect(notifications!.deliveryFailed.value, isFalse);
        }
      });
    }
  }
}
