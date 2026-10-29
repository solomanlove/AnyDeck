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
}
