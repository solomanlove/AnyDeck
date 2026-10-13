import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/app/window/multi_window_compat.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mixin.one/desktop_multi_window');
  const windowChannel = MethodChannel('mixin.one/desktop_multi_window/channels');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<Map<String, dynamic>> windows;
  late List<MethodCall> calls;
  late bool mirrorReady;
  setUp(() {
    windows = [];
    calls = [];
    mirrorReady = true;
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      calls.add(call);
      return mirrorReady;
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getAllWindows') return windows;
      if (call.method == 'createWindow') {
        final id = '${windows.length + 1}';
        windows.add({
          'windowId': id,
          'windowArgument': (call.arguments as Map)['arguments'],
        });
        return id;
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(windowChannel, null);
  });
  test('相同 APK 聚焦，不同路径创建独立窗口', () async {
    final first = await createAdbManageWindow(
      arguments: {'type': 'apk_details', 'path': '/tmp/中文 app.apk'},
    );
    final repeated = await createAdbManageWindow(
      arguments: {'type': 'apk_details', 'path': '/tmp/中文 app.apk'},
    );
    final second = await createAdbManageWindow(
      arguments: {'type': 'apk_details', 'path': '/tmp/second.apk'},
    );
    expect(repeated.windowId, first.windowId);
    expect(second.windowId, isNot(first.windowId));
    expect(windows, hasLength(2));
    expect(
      calls
          .where((c) => c.method == 'window_show')
          .elementAt(1)
          .arguments['windowId'],
      first.windowId,
    );
  });
  test('保留原有 console 单例和 mirror 按设备去重行为', () async {
    windows = [
      {
        'windowId': 'console',
        'windowArgument': jsonEncode({'type': 'console'}),
      },
      {
        'windowId': 'mirror',
        'windowArgument': jsonEncode({
          'type': 'mirror',
          'deviceId': 'device-A',
        }),
      },
    ];
    expect(
      (await createAdbManageWindow(arguments: {'type': 'console'})).windowId,
      'console',
    );
    expect(
      (await createAdbManageWindow(
        arguments: {'type': 'mirror', 'deviceId': 'device-A'},
      )).windowId,
      'mirror',
    );
    expect(
      (await createAdbManageWindow(
        arguments: {'type': 'mirror', 'deviceId': 'device-B'},
      )).windowId,
      isNot('mirror'),
    );
  });
  test('同设备窗口初始化未就绪时仍复用，避免重复采集', () async {
    mirrorReady = false;
    windows = [
      {
        'windowId': 'starting',
        'windowArgument': jsonEncode({'type': 'mirror', 'deviceId': 'device-A'}),
      },
    ];
    final reused = await createAdbManageWindow(
      arguments: {'type': 'mirror', 'deviceId': 'device-A'},
    );
    expect(reused.windowId, 'starting');
    expect(calls.where((call) => call.method == 'createWindow'), isEmpty);
    expect(calls.where((call) => call.method == 'invokeMethod'), hasLength(5));
  });
}
