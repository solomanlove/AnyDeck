import 'dart:async';

import 'package:any_deck/core/scrcpy/embedded_camera_backend.dart';
import 'package:any_deck/core/scrcpy/rust_device_session.dart';
import 'package:any_deck/core/scrcpy/scrcpy_camera_options.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends RustDeviceSession {
  _Session(this.events)
    : super(
        adb: 'adb',
        deviceId: 'phone',
        resolveJar: () async => 'jar',
        kind: 0,
      );
  final List<String> events;
  @override
  int get handle => 10;
  @override
  Future<void> start() async {
    events.add('rust.start');
  }

  @override
  void cancel() {
    events.add('rust.cancel');
  }

  @override
  Future<void> stop() async {
    events.add('rust.stop');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const virtual = MethodChannel('anydeck/virtual_camera');
  const texture = MethodChannel('anydeck/rust_texture');
  tearDown(() {
    messenger.setMockMethodCallHandler(virtual, null);
    messenger.setMockMethodCallHandler(texture, null);
  });

  test('先获得跨窗口租约再启动采集，停止采集后释放租约', () async {
    final events = <String>[];
    messenger.setMockMethodCallHandler(virtual, (call) async {
      events.add(call.method);
      if (call.method == 'acquirePreview') {
        expect(call.arguments, {'deviceId': 'phone'});
        return 42;
      }
      expect(call.arguments, {'token': 42});
      return null;
    });
    messenger.setMockMethodCallHandler(texture, (call) async {
      events.add(call.method);
      return call.method == 'register' ? 77 : null;
    });
    final backend = RustCameraBackend(_Session(events));
    expect(await backend.start(), 77);
    await backend.stop();
    expect(
      events.indexOf('acquirePreview'),
      lessThan(events.indexOf('rust.start')),
    );
    expect(
      events.indexOf('rust.stop'),
      lessThan(events.indexOf('releasePreview')),
    );
    expect(events.where((event) => event == 'releasePreview'), hasLength(1));
  });

  test('系统摄像头占用时原生拒绝租约，不启动本地镜头', () async {
    final events = <String>[];
    messenger.setMockMethodCallHandler(
      virtual,
      (_) async => throw PlatformException(code: 'cameraBusy'),
    );
    final backend = RustCameraBackend(_Session(events));
    await expectLater(
      backend.start(),
      throwsA(
        isA<CameraPreviewException>().having(
          (error) => error.messageKey,
          'messageKey',
          'virtualCameraPreviewBlocked',
        ),
      ),
    );
    await backend.stop();
    expect(events, isNot(contains('rust.start')));
  });

  test('取得租约前取消，迟到的租约会释放且不会启动镜头', () async {
    final events = <String>[];
    final acquired = Completer<int>();
    messenger.setMockMethodCallHandler(virtual, (call) async {
      events.add(call.method);
      if (call.method == 'acquirePreview') return acquired.future;
      return null;
    });
    final backend = RustCameraBackend(_Session(events));
    final starting = expectLater(
      backend.start(),
      throwsA(isA<CameraPreviewException>()),
    );
    final stopping = backend.stop();
    acquired.complete(9);
    await starting;
    await stopping;
    expect(events, isNot(contains('rust.start')));
    expect(events.where((event) => event == 'releasePreview'), hasLength(1));
  });
}
