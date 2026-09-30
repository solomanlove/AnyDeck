import 'package:any_deck/core/notifications/mac_notification_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
