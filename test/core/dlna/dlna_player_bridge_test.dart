import 'package:any_deck/core/dlna/dlna_player_bridge.dart';
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
}
