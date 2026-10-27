import 'dart:convert';

import 'package:any_deck/core/airplay/airplay_server_service.dart';
import 'package:any_deck/core/airplay/airplay_server_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用真实开窗 helper 验证 Engine 握手和切源确认，不加载 native 接收器。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windows = MethodChannel('mixin.one/desktop_multi_window');
  const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const session = AirPlaySessionData(
    id: 1000,
    serverName: 'AirPlay',
    rtspPort: 7000,
    videoPort: 7100,
    status: AirPlayServerStatus.mirrorStarting,
  );
  late List<String> events;
  late int readyAttempts;
  late bool switchAccepted;

  setUp(() {
    events = [];
    readyAttempts = 0;
    switchAccepted = true;
    messenger.setMockMethodCallHandler(windows, (call) async {
      events.add(call.method);
      if (call.method == 'getAllWindows') return [];
      if (call.method == 'createWindow') {
        final args =
            jsonDecode((call.arguments as Map)['arguments'] as String) as Map;
        expect(args['type'], 'mirror');
        expect(args['airplayHandle'], 1000);
        expect((call.arguments as Map)['hiddenAtLaunch'], true);
        return 'mirror-test';
      }
      return null;
    });
    messenger.setMockMethodCallHandler(channels, (call) async {
      final envelope = call.arguments as Map;
      final method = envelope['method'] as String;
      events.add(method);
      if (method == 'isFlutterReady') return ++readyAttempts > 1;
      if (method == 'switchIosMirrorSource') {
        expect((envelope['arguments'] as Map)['airplayHandle'], 1000);
        return switchAccepted;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(windows, null);
    messenger.setMockMethodCallHandler(channels, null);
  });

  test('等待 Engine 就绪且切源确认后才返回开窗成功', () async {
    expect(await openAirPlayMirrorWindow(session), true);
    expect(readyAttempts, 2);
    expect(
      events.indexOf('window_show'),
      greaterThan(events.indexOf('switchIosMirrorSource')),
    );
    expect(events.where((event) => event == 'createWindow'), hasLength(1));
  });

  test('切源未确认不能假报开窗成功，交由协调器重试', () async {
    switchAccepted = false;
    expect(await openAirPlayMirrorWindow(session), false);
    expect(events, isNot(contains('window_show')));
  });
}
