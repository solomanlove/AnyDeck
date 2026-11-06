import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/app/window/multi_window_compat.dart';
import 'package:any_deck/app/window/mirror/app_mirror_window_creation_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mixin.one/desktop_multi_window');
  const windowChannel = MethodChannel('mixin.one/desktop_multi_window/channels');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<Map<String, dynamic>> windows;
  late List<MethodCall> calls;
  late bool mirrorReady;
  late Duration createDelay;
  setUp(() {
    windows = [];
    calls = [];
    mirrorReady = true;
    createDelay = Duration.zero;
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      calls.add(call);
      return mirrorReady;
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getAllWindows') return windows;
      if (call.method == 'createWindow') {
        if (createDelay > Duration.zero) await Future<void>.delayed(createDelay);
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

  test('同一物理手机的应用窗口跨连接和分辨率变化仍复用', () async {
    windows = [
      {
        'windowId': 'fusion-usb',
        'windowArgument': jsonEncode({
          'type': 'mirror',
          'deviceId': 'USB-1',
          'physicalDeviceKey': 'PHONE-1',
          'newDisplay': '1080x2400/420',
          'startApp': 'com.example.gallery',
        }),
      },
    ];
    final reused = await createAdbManageWindow(arguments: {
      'type': 'mirror',
      'deviceId': '192.168.1.2:5555',
      'physicalDeviceKey': 'PHONE-1',
      'newDisplay': '1080x1920/420',
      'startApp': 'com.example.gallery',
    });
    expect(reused.windowId, 'fusion-usb');
    expect(calls.where((call) => call.method == 'createWindow'), isEmpty);
  });

  test('并发点击经主窗口创建队列只生成一个应用窗口', () async {
    createDelay = const Duration(milliseconds: 20);
    final arguments = {
      'type': 'mirror',
      'deviceId': 'USB-1',
      'physicalDeviceKey': 'PHONE-1',
      'newDisplay': '1080x1920/420',
      'startApp': 'com.example.gallery',
    };
    final ids = await Future.wait([
      AppMirrorWindowCreationGate.createLocal(arguments, const Size(500, 800), 'Gallery'),
      AppMirrorWindowCreationGate.createLocal(arguments, const Size(500, 800), 'Gallery'),
    ]);
    expect(ids, ['1', '1']);
    expect(calls.where((call) => call.method == 'createWindow'), hasLength(1));
  });

  test('子窗口创建请求交给主窗口处理', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getWindowDefinition') {
        return {'windowId': 'child', 'windowArgument': '{}'};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      calls.add(call);
      return call.method == 'invokeMethod' ? 'main-window-id' : true;
    });
    final id = await AppMirrorWindowCreationGate.create(
      {'type': 'mirror', 'deviceId': 'USB-1'},
      const Size(500, 800),
      'Gallery',
    );
    expect(id, 'main-window-id');
    expect(calls.where((call) => call.method == 'createWindow'), isEmpty);
    final remoteCall = calls.singleWhere((call) => call.method == 'invokeMethod');
    expect(remoteCall.arguments['method'], AppMirrorWindowCreationGate.methodName);
    expect(remoteCall.arguments['channel'], 'mixin.one/window_controller/0');
  });
}
