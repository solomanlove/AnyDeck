import 'dart:convert';

import 'package:any_deck/app/window/mirror/mirror_audio_focus_coordinator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windowsChannel = MethodChannel('mixin.one/desktop_multi_window');
  const methodChannel = MethodChannel(
    'mixin.one/desktop_multi_window/channels',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late List<Map<String, dynamic>> windows;

  setUp(() {
    calls.clear();
    windows = [
      {
        'windowId': 'usb',
        'windowArgument': jsonEncode({
          'type': 'mirror',
          'deviceId': 'USB-1',
          'physicalDeviceKey': 'PHONE-1',
        }),
      },
      {
        'windowId': 'wifi',
        'windowArgument': jsonEncode({
          'type': 'mirror',
          'deviceId': '192.168.1.2:5555',
          'physicalDeviceKey': 'PHONE-1',
          'startApp': 'com.example.gallery',
        }),
      },
      {
        'windowId': 'other',
        'windowArgument': jsonEncode({
          'type': 'mirror',
          'deviceId': 'USB-2',
          'physicalDeviceKey': 'PHONE-2',
        }),
      },
    ];
    messenger.setMockMethodCallHandler(windowsChannel, (call) async {
      if (call.method != 'getAllWindows') return null;
      return windows;
    });
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      return true;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(windowsChannel, null);
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  test('USB 与无线窗口按物理手机共享唯一音频焦点', () async {
    final focus = MirrorAudioFocusCoordinator();
    final muted = await focus.claim(
      currentWindowId: 'wifi',
      deviceId: '192.168.1.2:5555',
      physicalDeviceKey: 'PHONE-1',
      isAppMirror: true,
    );
    expect(muted, isFalse);
    expect(calls.where((call) => call.method == 'invokeMethod'), hasLength(1));
    final args = calls.single.arguments as Map;
    expect(args['arguments']['physicalDeviceKey'], 'PHONE-1');
    expect(args['arguments']['muted'], isTrue);
  });

  test('两个应用窗口并发申请时只让较新的数字窗口播放', () async {
    windows = [
      for (final id in ['9', '10'])
        {
          'windowId': id,
          'windowArgument': jsonEncode({
            'type': 'mirror',
            'deviceId': 'USB-1',
            'physicalDeviceKey': 'PHONE-1',
            'startApp': 'com.example.app$id',
          }),
        },
    ];
    final focus = MirrorAudioFocusCoordinator();
    final muted = await Future.wait([
      focus.claim(
        currentWindowId: '9',
        deviceId: 'USB-1',
        physicalDeviceKey: 'PHONE-1',
        isAppMirror: true,
      ),
      focus.claim(
        currentWindowId: '10',
        deviceId: 'USB-1',
        physicalDeviceKey: 'PHONE-1',
        isAppMirror: true,
      ),
    ]);
    expect(muted, [true, false]);
    final updates = calls.where((call) => call.method == 'invokeMethod');
    expect(updates, hasLength(2));
    for (final update in updates) {
      final args = update.arguments as Map;
      expect(args['arguments']['muted'], args['channel'].endsWith('/9'));
    }
  });
}
