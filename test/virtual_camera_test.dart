import 'dart:async';

import 'package:any_deck/core/virtual_camera/virtual_camera_controller.dart';
import 'package:any_deck/core/virtual_camera/virtual_camera_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('anydeck/virtual_camera');
const _ready = <String, Object?>{
  'supported': true,
  'installed': true,
  'activation': 'ready',
  'error': '',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  ProviderContainer container() {
    final value = ProviderContainer(
      overrides: [
        virtualCameraHostProvider.overrideWithValue(true),
        virtualCameraPathsProvider.overrideWith(
          (ref) async => {
            'adbPath': '/tools/adb',
            'jarPath': '/resources/scrcpy-server.jar',
          },
        ),
      ],
    );
    value.listen(virtualCameraProvider, (_, _) {});
    return value;
  }

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test('启用先停止本地预览，关闭页面保留会议摄像头，重开读取原生状态', () async {
    final calls = <String>[];
    var native = {..._ready};
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      if (call.method == 'configure') {
        final args = call.arguments as Map;
        expect(args['adbPath'], '/tools/adb');
        expect(args['jarPath'], '/resources/scrcpy-server.jar');
        expect(args['labels'], {'stop': 'Stop'});
        native = {
          ..._ready,
          'enabled': true,
          'deviceId': args['deviceId'],
          'front': args['front'],
        };
      }
      return native;
    });
    final first = container();
    await Future<void>.delayed(Duration.zero);
    expect(first.read(virtualCameraProvider).messageKey, 'virtualCameraReady');
    await first
        .read(virtualCameraProvider.notifier)
        .enable(
          deviceId: 'phone',
          front: true,
          labels: {'stop': 'Stop'},
          stopPreview: () async {
            calls.add('stopPreview');
          },
        );
    expect(calls, ['status', 'stopPreview', 'configure']);
    expect(first.read(virtualCameraProvider).ownsDevice('phone'), true);
    first.dispose();
    expect(calls.where((method) => method == 'configure'), hasLength(1));
    final second = container();
    addTearDown(second.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(second.read(virtualCameraProvider).enabled, true);
    expect(second.read(virtualCameraProvider).front, true);
  });

  test('释放本地预览失败时不调用原生开启，重复启用被合并', () async {
    final stop = Completer<void>();
    var configurations = 0;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'configure') configurations++;
      return _ready;
    });
    final value = container();
    addTearDown(value.dispose);
    await Future<void>.delayed(Duration.zero);
    final controller = value.read(virtualCameraProvider.notifier);
    final starting = controller.enable(
      deviceId: 'phone',
      front: false,
      labels: {},
      stopPreview: () => stop.future,
    );
    await controller.enable(
      deviceId: 'phone',
      front: false,
      labels: {},
      stopPreview: () async => fail('duplicate start'),
    );
    stop.completeError(StateError('/private/internal/path'));
    await starting;
    expect(configurations, 0);
    expect(value.read(virtualCameraProvider).busy, false);
    expect(value.read(virtualCameraProvider).messageKey, 'virtualCameraFailed');
  });

  test('迟到的轮询结果不能覆盖停止操作', () async {
    final pending = Completer<Map<String, Object?>>();
    var reads = 0;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'status' && ++reads == 2) return pending.future;
      return call.method == 'configure'
          ? _ready
          : {..._ready, 'enabled': true, 'deviceId': 'phone'};
    });
    final value = container();
    addTearDown(value.dispose);
    await Future<void>.delayed(Duration.zero);
    final controller = value.read(virtualCameraProvider.notifier);
    final reading = controller.refresh();
    await controller.disable();
    pending.complete({..._ready, 'enabled': true, 'deviceId': 'phone'});
    await reading;
    expect(value.read(virtualCameraProvider).enabled, false);
  });

  test('未批准扩展不启用手机，未知原生异常只显示公共错误', () async {
    var configured = false;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'configure') configured = true;
      return {'supported': true, 'activation': 'needsApproval'};
    });
    final value = container();
    addTearDown(value.dispose);
    await Future<void>.delayed(Duration.zero);
    await value
        .read(virtualCameraProvider.notifier)
        .enable(
          deviceId: 'phone',
          front: false,
          labels: {},
          stopPreview: () async => fail('must not stop local preview'),
        );
    expect(configured, false);
    expect(
      const VirtualCameraState(error: '/private/internal/path').messageKey,
      'virtualCameraFailed',
    );
  });

  test('设置跳转接受 void 返回，重复点击合并且不能当成扩展已获批', () async {
    final opened = Completer<void>();
    final calls = <String>[];
    var native = <String, Object?>{
      'supported': true,
      'activation': 'needsApproval',
    };
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      if (call.method == 'openSettings') {
        await opened.future;
        return null;
      }
      return native;
    });
    final value = container();
    addTearDown(value.dispose);
    await Future<void>.delayed(Duration.zero);
    final controller = value.read(virtualCameraProvider.notifier);
    final opening = controller.openSettings();
    await controller.openSettings();
    expect(value.read(virtualCameraProvider).busy, true);
    opened.complete();
    await opening;
    expect(calls, ['status', 'openSettings', 'status']);
    expect(value.read(virtualCameraProvider).ready, false);
    expect(value.read(virtualCameraProvider).activation, 'needsApproval');
    native = _ready;
    await controller.refresh();
    expect(value.read(virtualCameraProvider).ready, true);
  });

  test('系统设置打开失败保留待批准状态并可重试', () async {
    var failOpen = true;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'openSettings') {
        if (failOpen) throw PlatformException(code: 'settings_open_failed');
        return null;
      }
      return {'supported': true, 'activation': 'needsApproval'};
    });
    final value = container();
    addTearDown(value.dispose);
    await Future<void>.delayed(Duration.zero);
    final controller = value.read(virtualCameraProvider.notifier);
    await controller.openSettings();
    expect(value.read(virtualCameraProvider).ready, false);
    expect(value.read(virtualCameraProvider).activation, 'needsApproval');
    expect(value.read(virtualCameraProvider).busy, false);
    expect(
      value.read(virtualCameraProvider).messageKey,
      'virtualCameraOpenSettingsFailed',
    );
    failOpen = false;
    await controller.openSettings();
    expect(value.read(virtualCameraProvider).error, isNull);
    expect(value.read(virtualCameraProvider).activation, 'needsApproval');
  });

  test('设置跳转期间销毁页面会结束等待且不发布迟到结果', () async {
    final opened = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call.method);
      if (call.method == 'openSettings') {
        await opened.future;
        return null;
      }
      return {'supported': true, 'activation': 'needsApproval'};
    });
    final value = container();
    await Future<void>.delayed(Duration.zero);
    final opening = value.read(virtualCameraProvider.notifier).openSettings();
    value.dispose();
    await expectLater(opening, completes);
    opened.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['status', 'openSettings']);
  });
}
