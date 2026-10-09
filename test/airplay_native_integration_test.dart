import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/airplay/airplay_server_service.dart';
import 'package:any_deck/core/airplay/airplay_server_state.dart';

/// 显式指定本机构建的 dylib 才运行，验证后台 Isolate 与主 Isolate 共享 native 会话。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = Platform.environment['ANYDECK_DEVICE_BRIDGE'];
  test('native lifecycle shares sessions across isolates and restarts', () async {
    const channel = MethodChannel('anydeck/rust_texture');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return call.method == 'register' ? 1 : null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final service = AirPlayServerService.instance;
    expect(service.isSupported, isTrue);
    for (var i = 0; i < 2; i++) {
      final session = await service.start(
        name: 'AnyDeck-FFI-Regression',
        rtspPort: 7040,
      );
      try {
        expect(session.id, greaterThan(0));
        expect(service.getStatus(session.id), AirPlayServerStatus.idle);
        expect(service.getDimensions(session.id), isNull);
        expect(session.textureId, 1);
      } finally {
        await service.stop(session);
      }
      expect(service.getStatus(session.id), AirPlayServerStatus.stopped);
    }
  }, skip: !Platform.isMacOS || library == null || library.isEmpty);
}
