import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/scrcpy/embedded_scrcpy_service.dart';
import 'package:any_deck/core/scrcpy/scrcpy_camera_options.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟实时 adb 列表与每条 transport 的硬件身份，不依赖设备缓存。
class TransportAdb extends AdbService {
  String devices = '';
  int listCode = 0;
  final serials = <String, String>{};
  final bootSerials = <String, String>{};
  final calls = <List<String>>[];
  final timeouts = <Duration>[];
  Completer<void>? listGate;

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    calls.add(args);
    timeouts.add(timeout);
    if (args.first == 'devices') {
      await listGate?.future;
      return AdbResult(
        exitCode: listCode,
        stdout: 'List of devices attached\n$devices\n',
        stderr: '',
      );
    }
    final serial = args.last == 'ro.boot.serialno'
        ? bootSerials[args[1]]
        : serials[args[1]];
    return AdbResult(
      exitCode: serial == null ? 1 : 0,
      stdout: serial ?? '',
      stderr: '',
    );
  }
}

/// 模拟 scrcpy server 退出，不调用原生 Rust/Texture。
class MirrorProcess extends Fake implements Process {
  final ended = Completer<int>();
  @override
  Future<int> get exitCode => ended.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!ended.isCompleted) ended.complete(0);
    return true;
  }
}

/// 验证会话启动参数、旧资源释放和启动期间取消，完全隔离真机进程。
class TransportMirrors extends Fake implements EmbeddedScrcpyService {
  final textures = <String, int>{};
  final processes = <String, MirrorProcess>{};
  final events = <String>[];
  final starts = <({String id, String? display, String? app, bool muted})>[];
  final failStart = <String>{};
  final stopGates = <String, Completer<void>>{};
  Completer<void>? startGate;
  int _nextTexture = 0;

  @override
  bool isActive(String deviceId) => textures.containsKey(deviceId);
  @override
  int? getTextureId(String deviceId) => textures[deviceId];
  @override
  Process? getServerProcess(String deviceId) => processes[deviceId];

  @override
  Future<int> start({
    required String deviceId,
    String? newDisplay,
    String? startApp,
    ScrcpyCameraOptions? camera,
    bool initiallyMuted = false,
  }) async {
    events.add('start:$deviceId');
    starts.add((
      id: deviceId,
      display: newDisplay,
      app: startApp,
      muted: initiallyMuted,
    ));
    await startGate?.future;
    if (failStart.contains(deviceId)) throw StateError('device disconnected');
    processes[deviceId] = MirrorProcess();
    return textures[deviceId] = ++_nextTexture;
  }

  @override
  Future<void> stop(String deviceId) async {
    events.add('stop:$deviceId');
    textures.remove(deviceId);
    processes.remove(deviceId)?.kill();
    await stopGates[deviceId]?.future;
    events.add('stopped:$deviceId');
  }
}
