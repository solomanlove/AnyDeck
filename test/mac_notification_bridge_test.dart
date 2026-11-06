import 'package:any_deck/core/notifications/mac_notification_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('交互授权保留错误与缺失响应，旧入口继续返回 false', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    const channel = MethodChannel('test/notification_authorization');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    dynamic response;
    messenger.setMockMethodCallHandler(channel, (_) async {
      if (response is PlatformException) throw response;
      return response;
    });
    final bridge = MacNotificationBridge(channel: channel);
    try {
      for (final granted in [true, false]) {
        response = granted;
        expect(await bridge.requestAuthorizationOrThrow(), granted);
        expect(await bridge.requestAuthorization(), granted);
      }
      for (final failure in [null, 42, PlatformException(code: 'authorization_failed')]) {
        response = failure;
        await expectLater(
          bridge.requestAuthorizationOrThrow(),
          throwsA(failure == 42
              ? isA<TypeError>()
              : isA<PlatformException>().having(
                  (error) => error.code,
                  'code',
                  failure == null ? 'invalid_authorization_response' : 'authorization_failed',
                )),
        );
        expect(await bridge.requestAuthorization(), isFalse);
      }
    } finally {
      bridge.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test(
    'forwards device title and message subtitle while preserving payload',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      const channel = MethodChannel('test/notifications');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      final bridge = MacNotificationBridge(channel: channel);
      try {
        expect(
          await bridge.showNotification(
            id: 'a',
            title: '工作手机 · A123 · 微信',
            subtitle: '张三',
            body: '',
            payload: {'installationId': 'inst_a', 'androidUserId': 10},
          ),
          isTrue,
        );
        expect(calls.single.arguments, containsPair('subtitle', '张三'));
        expect(calls.single.arguments, containsPair('body', ''));
        expect(
          (calls.single.arguments as Map)['payload'],
          containsPair('installationId', 'inst_a'),
        );
        await bridge.showNotification(
          id: 'connection',
          title: 'Phone connected',
        );
        expect(calls.last.arguments, containsPair('subtitle', ''));
      } finally {
        bridge.dispose();
        messenger.setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test('permission errors and missing or malformed responses remain unknown', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    const channel = MethodChannel('test/notification_permission');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var reply = <String, dynamic>{'value': null};
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (reply['throws'] == true) {
        throw PlatformException(code: 'unavailable');
      }
      return reply['value'];
    });
    final bridge = MacNotificationBridge(channel: channel);
    try {
      for (final state in [null, 'new_unknown_status', 42]) {
        reply = {'value': state};
        expect(await bridge.getAuthorizationStatus(), 'unknown');
      }
      reply = {'throws': true};
      expect(await bridge.getAuthorizationStatus(), 'unknown');
      for (final state in ['authorized', 'provisional', 'denied', 'notDetermined']) {
        reply = {'value': state};
        expect(await bridge.getAuthorizationStatus(), state);
      }
      expect(calls, everyElement('getAuthorizationStatus'));
    } finally {
      bridge.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('来件使用独立能力入口并传递本地化按钮和请求身份', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    const channel = MethodChannel('test/incoming_offer');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    final bridge = MacNotificationBridge(channel: channel);
    try {
      expect(
        await bridge.showIncomingFileOffer(
          id: 'offer_1',
          title: '收到文件请求',
          body: '2 个文件',
          acceptLabel: '接收',
          rejectLabel: '拒绝',
          payload: const {
            'type': 'harmony_share_offer',
            'offerToken': 'opaque-current-offer',
          },
        ),
        isTrue,
      );
      expect(calls.single.method, 'showIncomingFileOffer');
      expect(calls.single.arguments, {
        'id': 'offer_1',
        'title': '收到文件请求',
        'body': '2 个文件',
        'acceptLabel': '接收',
        'rejectLabel': '拒绝',
        'payload': {
          'type': 'harmony_share_offer',
          'offerToken': 'opaque-current-offer',
        },
      });
    } finally {
      bridge.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('旧桥接、发送失败及异常返回值允许来件弹窗兜底', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    const channel = MethodChannel('test/incoming_offer_failure');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    dynamic response;
    messenger.setMockMethodCallHandler(channel, (_) async {
      if (response is Exception) throw response;
      return response;
    });
    final bridge = MacNotificationBridge(channel: channel);
    try {
      for (final value in [
        null,
        false,
        42,
        MissingPluginException('old bridge'),
        PlatformException(code: 'add_failed'),
      ]) {
        response = value;
        expect(
          await bridge.showIncomingFileOffer(
            id: 'offer_1',
            title: 'Incoming files',
            body: '2 files',
            acceptLabel: 'Accept',
            rejectLabel: 'Reject',
            payload: const {'type': 'harmony_share_offer', 'offerToken': '1'},
          ),
          isFalse,
        );
      }
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      response = true;
      expect(
        await bridge.showIncomingFileOffer(
          id: 'offer_1',
          title: 'Incoming files',
          body: '',
          acceptLabel: 'Accept',
          rejectLabel: 'Reject',
          payload: const {},
        ),
        isFalse,
      );
    } finally {
      bridge.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('原生动作回调保留通知身份，交由来件协调器验证有效性', () async {
    const channel = MethodChannel('test/incoming_offer_click');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final bridge = MacNotificationBridge(channel: channel);
    try {
      final click = bridge.clickStream.first;
      const payload = {
        'type': 'harmony_share_offer',
        'offerToken': 'live-token',
        'notificationId': 'actual-notification-id',
        'notificationAction': 'accept',
      };
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onNotificationClicked', payload),
        ),
        (_) {},
      );
      expect(await click, payload);
    } finally {
      bridge.dispose();
    }
  });
}
