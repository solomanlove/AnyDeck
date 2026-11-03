import 'package:any_deck/core/dlna/dlna_player_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MethodChannel 将空进度编码为 int 时仍能读取', () async {
    const channel = MethodChannel('any_deck/dlna_player');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => 0);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    expect(await DlnaPlayerBridge.readNumber('duration'), 0.0);
  });

  test('MethodChannel 保留非零 double 进度', () async {
    const channel = MethodChannel('any_deck/dlna_player');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => 12.5);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    expect(await DlnaPlayerBridge.readNumber('position'), 12.5);
  });

  test('主程序主题同步到 DLNA 与 AirPlay 原生播放器', () async {
    const dlna = MethodChannel('any_deck/dlna_player');
    const airplay = MethodChannel('any_deck/airplay_player');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(dlna, (call) async {
      calls.add('dlna:${call.method}:${call.arguments}');
      return null;
    });
    messenger.setMockMethodCallHandler(airplay, (call) async {
      calls.add('airplay:${call.method}:${call.arguments}');
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(dlna, null));
    addTearDown(() => messenger.setMockMethodCallHandler(airplay, null));

    for (final mode in ThemeMode.values) {
      await DlnaPlayerBridge.syncAppearance(mode);
      expect(calls, contains('dlna:setAppearance:${mode.name}'));
      expect(calls, contains('airplay:setAppearance:${mode.name}'));
    }
  });
}
