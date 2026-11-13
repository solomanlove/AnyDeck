import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/airplay/airplay_server_service.dart';
import 'package:any_deck/core/airplay/airplay_server_state.dart';
import 'package:any_deck/core/airplay/airplay_video_bridge.dart';

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
        final video = AirPlayVideoBridge();
        final media = video.read(session.id)!;
        expect(media['url'], isNull);
        expect(media['generation'], 0);
        video.report(session.id, 99, {'state': 2});
        expect(video.read(session.id)!['revision'], 0);
      } finally {
        await service.stop(session);
      }
      expect(service.getStatus(session.id), AirPlayServerStatus.stopped);
    }
  }, skip: !Platform.isMacOS || library == null || library.isEmpty);

  test('simultaneous Bonjour registrations confirm distinct stable names', () async {
    const channel = MethodChannel('anydeck/rust_texture');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final service = AirPlayServerService.instance;
    final sessions = <AirPlaySessionData>[];
    addTearDown(() async {
      for (final session in sessions) {
        await service.stop(session);
      }
      messenger.setMockMethodCallHandler(channel, null);
    });
    final requested = 'AnyDeck-FFI-Concurrent-$pid';
    final names = await Future.wait([
      for (final code in ['AA0011', 'BB0022'])
        service.start(
          name: requested,
          fallbackNames: ['$requested-$code', '$requested-${code}112233', '$requested-${code}11223344556677889900'],
          rtspPort: 0,
        ).then((session) {
          sessions.add(session);
          return session;
        }),
    ]);
    expect(names.map((session) => session.serverName).toSet(), hasLength(2));
    for (final session in names) {
      expect(session.isPublished, isTrue);
      expect(session.serverName, isNot(contains('(2)')));
      expect(service.getPublishedName(session.id), session.serverName);
      expect(service.getPublicationStatus(session.id), 1);
    }
    final loser = names.firstWhere((session) => session.serverName != requested);
    final stableName = loser.serverName;
    await service.stop(loser);
    sessions.remove(loser);
    final restarted = await service.start(
      name: requested,
      fallbackNames: [stableName, '$stableName-112233', '$stableName-445566'],
      rtspPort: 0,
    );
    sessions.add(restarted);
    expect(restarted.serverName, stableName);
  }, skip: !Platform.isMacOS || library == null || library.isEmpty);
}
