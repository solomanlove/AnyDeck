import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrcpy_flutter/scrcpy_flutter.dart';

import '../adb/adb_service.dart';
import '../providers/app_providers.dart';

class EmbeddedScrcpySession {
  EmbeddedScrcpySession({
    required this.deviceId,
    required this.port,
    required this.serverProcess,
    required this.textureId,
    required this.startedAt,
  });

  final String deviceId;
  final int port;
  final Process serverProcess;
  final int textureId;
  final DateTime startedAt;
}

class EmbeddedScrcpyService {
  EmbeddedScrcpyService(this._adbService);

  final AdbService _adbService;
  final Map<String, EmbeddedScrcpySession> _sessions = {};

  bool isActive(String deviceId) => _sessions.containsKey(deviceId);
  int? getTextureId(String deviceId) => _sessions[deviceId]?.textureId;

  Future<String> _extractScrcpyServerJar() async {
    final bytes = await rootBundle.load('assets/scrcpy/scrcpy-server.jar');
    final dir = Directory('${Directory.systemTemp.path}/adb_manage_scrcpy');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/scrcpy-server.jar');
    await file.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
    return file.path;
  }

  Future<int> _findFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<int> start({required String deviceId}) async {
    if (_sessions.containsKey(deviceId)) {
      return _sessions[deviceId]!.textureId;
    }

    // 1. Resolve and push scrcpy-server.jar
    final serverJar = await _extractScrcpyServerJar();
    if (!File(serverJar).existsSync()) {
      throw Exception('scrcpy-server not found on host. Failed to extract asset.');
    }

    final pushRes = await _adbService.run([
      '-s', deviceId,
      'push', serverJar, '/data/local/tmp/scrcpy-server.jar'
    ]);
    if (!pushRes.isSuccess) {
      throw Exception('Failed to push scrcpy-server.jar: ${pushRes.stderr}');
    }

    // 2. Allocate free port and setup forward tunnel
    final localPort = await _findFreePort();
    final forwardRes = await _adbService.run([
      '-s', deviceId,
      'forward', 'tcp:$localPort', 'localabstract:scrcpy_00000000'
    ]);
    if (!forwardRes.isSuccess) {
      throw Exception('Failed to setup adb forward: ${forwardRes.stderr}');
    }

    // 3. Start scrcpy-server process on Android
    final adbPath = _adbService.executable;
    final serverProcess = await Process.start(adbPath, [
      '-s', deviceId,
      'shell',
      'CLASSPATH=/data/local/tmp/scrcpy-server.jar',
      'app_process', '/', 'com.genymobile.scrcpy.Server',
      '4.0',
      'scid=0',
      'log_level=verbose',
      'audio=false',
      'control=true',
      'tunnel_forward=true',
      'display_id=0',
    ]);

    // Handle stdout/stderr for logging
    serverProcess.stdout.transform(utf8.decoder).listen((data) {
      stdout.write('[scrcpy-server stdout] $data');
    });
    serverProcess.stderr.transform(utf8.decoder).listen((data) {
      stderr.write('[scrcpy-server stderr] $data');
    });

    // 4. Wait for server to bind & listen
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    // 5. Connect C++ client via Native Plugin
    try {
      final textureId = await ScrcpyFlutter.startMirroring(
        deviceId: deviceId,
        port: localPort,
      );

      final session = EmbeddedScrcpySession(
        deviceId: deviceId,
        port: localPort,
        serverProcess: serverProcess,
        textureId: textureId,
        startedAt: DateTime.now(),
      );

      _sessions[deviceId] = session;
      return textureId;
    } catch (e) {
      // Cleanup on failure
      serverProcess.kill();
      await _adbService.run(['-s', deviceId, 'forward', '--remove', 'tcp:$localPort']);
      rethrow;
    }
  }

  Future<void> stop(String deviceId) async {
    final session = _sessions.remove(deviceId);
    if (session == null) return;

    try {
      await ScrcpyFlutter.stopMirroring(deviceId: deviceId);
    } catch (e) {
      // Ignored during stop
    }

    session.serverProcess.kill();
    await _adbService.run(['-s', deviceId, 'forward', '--remove', 'tcp:${session.port}']);
  }

  void stopAll() {
    final deviceIds = List<String>.from(_sessions.keys);
    for (final id in deviceIds) {
      stop(id);
    }
  }
}

// Riverpod Provider definitions
final embeddedScrcpyServiceProvider = Provider<EmbeddedScrcpyService>((ref) {
  final adbService = ref.watch(adbServiceProvider);
  final service = EmbeddedScrcpyService(adbService);
  ref.onDispose(service.stopAll);
  return service;
});

class ActiveEmbeddedMirrorNotifier extends Notifier<int?> {
  ActiveEmbeddedMirrorNotifier(this.deviceId);

  final String deviceId;

  @override
  int? build() {
    // Keep provider alive so session state is preserved when UI rebuilds or switch tabs
    ref.keepAlive();
    return ref.watch(embeddedScrcpyServiceProvider).getTextureId(deviceId);
  }

  Future<void> toggleMirroring() async {
    final service = ref.read(embeddedScrcpyServiceProvider);
    if (service.isActive(deviceId)) {
      await service.stop(deviceId);
      state = null;
    } else {
      try {
        final textureId = await service.start(deviceId: deviceId);
        state = textureId;
      } catch (e) {
        state = null;
        rethrow;
      }
    }
  }
  
  Future<void> forceStop() async {
    final service = ref.read(embeddedScrcpyServiceProvider);
    if (service.isActive(deviceId)) {
      await service.stop(deviceId);
      state = null;
    }
  }
}

final activeEmbeddedMirrorProvider = NotifierProvider.family<ActiveEmbeddedMirrorNotifier, int?, String>(
  ActiveEmbeddedMirrorNotifier.new,
);
