import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/scrcpy/embedded_scrcpy_service.dart';
import 'package:any_deck/core/scrcpy/scrcpy_camera_options.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 使用假进程验证会话生命周期，不执行 ADB 或访问手机摄像头。
class CameraServerProcess extends Fake implements Process {
  final done = Completer<int>();
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode => done.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!done.isCompleted) done.complete(0);
    return true;
  }
}

class CameraAdbFake extends AdbService {
  final commands = <List<String>>[];
  final launches = <List<String>>[];
  int sdk = 36;
  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(args);
    return AdbResult(
      exitCode: 0,
      stdout: args.contains('getprop') ? '$sdk' : '',
      stderr: '',
    );
  }

  @override
  Future<Process> start(List<String> args) async {
    launches.add(args);
    return CameraServerProcess();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('scrcpy_flutter');
  late List<MethodCall> native;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'settings.mirrorAudioEnabled': true,
    });
    native = [];
    messenger.setMockMessageHandler(
      'flutter/assets',
      (_) async => ByteData.sublistView(
        await File('assets/scrcpy/scrcpy-server.jar').readAsBytes(),
      ),
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      native.add(call);
      return call.method == 'startMirroring' ? native.length : null;
    });
  });
  tearDown(() {
    messenger.setMockMessageHandler('flutter/assets', null);
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('摄像头复用 Texture 协议，独立 socket/会话且无音频，不误停屏幕投屏', () async {
    final adb = CameraAdbFake();
    final service = EmbeddedScrcpyService(adb);
    final options = ScrcpyCameraOptions(deviceId: 'phone', front: true);
    addTearDown(() async {
      await service.stop(options.sessionId);
      await service.stop('phone');
    });
    await service.start(deviceId: 'phone');
    await service.start(deviceId: 'phone', camera: options);
    expect(adb.launches[0], contains('display_id=0'));
    expect(adb.launches[0], contains('audio=true'));
    expect(
      adb.launches[1],
      containsAll([
        'video_source=camera',
        'camera_facing=front',
        'audio=false',
        'video_codec=h264',
        'clipboard_autosync=false',
        'max_size=1280',
      ]),
    );
    expect(adb.launches[1], isNot(contains('display_id=0')));
    expect(adb.launches[1], contains('scid=${options.scid}'));
    expect(options.socketName, isNot('scrcpy_00000000'));
    final start = native.lastWhere((call) => call.method == 'startMirroring');
    expect(start.arguments['deviceId'], options.sessionId);
    expect(start.arguments['audio'], false);
    await service.stop(options.sessionId);
    expect(service.isActive('phone'), true);
    expect(service.isActive(options.sessionId), false);
    expect(adb.commands.last[1], 'phone');
    expect(native.last.arguments['deviceId'], options.sessionId);
  });

  test('Android 11 拒绝摄像头并回收转发，不启动服务', () async {
    final adb = CameraAdbFake()..sdk = 30;
    final service = EmbeddedScrcpyService(adb);
    await expectLater(
      service.start(
        deviceId: 'phone',
        camera: ScrcpyCameraOptions(deviceId: 'phone', front: false),
      ),
      throwsA(isA<CameraPreviewException>()),
    );
    expect(adb.launches, isEmpty);
    expect(adb.commands.last, contains('--remove'));
  });

  test('取消令牌拒绝迟到启动，每次摄像头会话 ID 独立', () async {
    final a = ScrcpyCameraOptions(deviceId: 'phone', front: false)..cancel();
    final b = ScrcpyCameraOptions(deviceId: 'phone', front: false);
    expect(a.sessionId, isNot(b.sessionId));
    expect(b.serverArguments, contains('camera_facing=back'));
    final adb = CameraAdbFake();
    await expectLater(
      EmbeddedScrcpyService(adb).start(deviceId: 'phone', camera: a),
      throwsA(isA<CameraPreviewException>()),
    );
    expect(adb.commands, isEmpty);
  });
}
