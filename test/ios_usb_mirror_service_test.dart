import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/ios/ios_usb_mirror_service.dart';

/// 模拟原生首帧完成与取消，确保 UI 不将启动请求当作已得到可用画面。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(IosUsbMirrorService.channel, null),
  );

  test('texture is exposed only after native first-frame completion', () async {
    final frame = Completer<int>();
    messenger.setMockMethodCallHandler(IosUsbMirrorService.channel, (
      call,
    ) async {
      if (call.method == 'start') return frame.future;
      return null;
    });
    final service = IosUsbMirrorService();
    final starting = service.start('phone');
    expect(service.texture('phone'), isNull);
    frame.complete(42);
    expect(await starting, 42);
    await service.stop('phone');
    expect(service.texture('phone'), isNull);
  }, skip: !Platform.isMacOS);

  test('native registration failure never becomes an active mirror', () async {
    messenger.setMockMethodCallHandler(
      IosUsbMirrorService.channel,
      (_) async => 0,
    );
    final service = IosUsbMirrorService();
    await expectLater(service.start('phone'), throwsStateError);
    expect(service.texture('phone'), isNull);
  }, skip: !Platform.isMacOS);

  test(
    'stop while waiting for native first frame cancels the startup',
    () async {
      final frame = Completer<int>();
      messenger.setMockMethodCallHandler(IosUsbMirrorService.channel, (
        call,
      ) async {
        if (call.method == 'start') return frame.future;
        if (call.method == 'stop') {
          frame.completeError(
            PlatformException(
              code: 'iosUsbCaptureStopped',
              details: {'stage': 'discovering', 'devices': []},
            ),
          );
        }
        return null;
      });
      final service = IosUsbMirrorService();
      final starting = service.start('phone');
      final assertion = expectLater(
        starting,
        throwsA(isA<PlatformException>()),
      );
      await service.stop('phone');
      await assertion;
      expect(service.texture('phone'), isNull);
    },
    skip: !Platform.isMacOS,
  );
}
