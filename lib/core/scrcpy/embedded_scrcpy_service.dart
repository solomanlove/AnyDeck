import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrcpy_flutter/scrcpy_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Process? getServerProcess(String deviceId) => _sessions[deviceId]?.serverProcess;

  Future<String> _extractScrcpyServerJar() async {
    final bytes = await rootBundle.load('assets/scrcpy/scrcpy-server.jar');
    final dir = Directory('${Directory.systemTemp.path}/any_deck_scrcpy');
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

  Future<int> start({
    required String deviceId,
    String? newDisplay,
    String? startApp,
  }) async {
    if (_sessions.containsKey(deviceId)) {
      return _sessions[deviceId]!.textureId;
    }

    // 1. Resolve and push scrcpy-server.jar
    final serverJar = await _extractScrcpyServerJar();
    if (!File(serverJar).existsSync()) {
      throw Exception(
        'scrcpy-server not found on host. Failed to extract asset.',
      );
    }

    final pushRes = await _adbService.run([
      '-s',
      deviceId,
      'push',
      serverJar,
      '/data/local/tmp/scrcpy-server.jar',
    ]);
    if (!pushRes.isSuccess) {
      throw Exception('Failed to push scrcpy-server.jar: ${pushRes.stderr}');
    }

    // 2. Allocate free port and setup forward tunnel
    final localPort = await _findFreePort();
    final forwardRes = await _adbService.run([
      '-s',
      deviceId,
      'forward',
      'tcp:$localPort',
      'localabstract:scrcpy_00000000',
    ]);
    if (!forwardRes.isSuccess) {
      throw Exception('Failed to setup adb forward: ${forwardRes.stderr}');
    }

    // 读取设备 SDK 版本以做音频转发降级保护 (Android 10及以下系统限制不支持)
    int sdkVersion = 0;
    try {
      final sdkRes = await _adbService.run([
        '-s',
        deviceId,
        'shell',
        'getprop',
        'ro.build.version.sdk',
      ]);
      if (sdkRes.isSuccess) {
        sdkVersion = int.tryParse(sdkRes.stdout.trim()) ?? 0;
      }
    } catch (e) {
      stdout.writeln('Failed to get device SDK version: $e');
    }
    final bool isAudioSupported = sdkVersion >= 30; // Android 11+ (API 30+)

    // 确保从 SharedPreferences 中获取最新的设置，防止 Isolate 异步加载延迟
    final prefs = await SharedPreferences.getInstance();
    final bool mirrorAudioEnabled = (prefs.getBool('settings.mirrorAudioEnabled') ?? true) && isAudioSupported;
    final int bitrate = prefs.getInt('settings.mirrorVideoBitrate') ?? 8000000;
    final int maxSize = prefs.getInt('settings.mirrorMaxSize') ?? 1080;

    // 3. Start scrcpy-server process on Android
    final adbPath = _adbService.executable;
    final serverProcess = await Process.start(adbPath, [
      '-s',
      deviceId,
      'shell',
      'CLASSPATH=/data/local/tmp/scrcpy-server.jar',
      'app_process',
      '/',
      'com.genymobile.scrcpy.Server',
      '4.0',
      'scid=0',
      'log_level=verbose',
      'audio=${mirrorAudioEnabled ? "true" : "false"}',
      'video_bit_rate=$bitrate',
      if (maxSize > 0) 'max_size=$maxSize',
      'control=true',
      'tunnel_forward=true',
      if (newDisplay != null) ...[
        'new_display=$newDisplay',
        'vd_system_decorations=false',
      ] else
        'display_id=0',
    ]);

    // Handle stdout/stderr for logging and parsing display ID
    final displayCompleter = Completer<int>();
    void handleLogData(String data) {
      if (newDisplay != null && !displayCompleter.isCompleted) {
        final match = RegExp(r'New display:.*\(id=(\d+)\)', caseSensitive: false).firstMatch(data);
        if (match != null) {
          final id = int.tryParse(match.group(1) ?? '');
          if (id != null) {
            displayCompleter.complete(id);
          }
        }
      }
    }

    serverProcess.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stdout.writeln('[scrcpy-server stdout] $line');
      handleLogData(line);
    });
    serverProcess.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stderr.writeln('[scrcpy-server stderr] $line');
      handleLogData(line);
    });

    // 4. Wait for server to bind & listen
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    // 4. Connect C++ client via Native Plugin (Connect first to avoid handshake deadlock)
    int textureId;
    try {
      textureId = await ScrcpyFlutter.startMirroring(
        deviceId: deviceId,
        port: localPort,
        audio: mirrorAudioEnabled,
      );

      final session = EmbeddedScrcpySession(
        deviceId: deviceId,
        port: localPort,
        serverProcess: serverProcess,
        textureId: textureId,
        startedAt: DateTime.now(),
      );

      _sessions[deviceId] = session;
    } catch (e) {
      // Cleanup on failure
      serverProcess.kill();
      await _adbService.run([
        '-s',
        deviceId,
        'forward',
        '--remove',
        'tcp:$localPort',
      ]);
      rethrow;
    }

    // 5. Once connected, the server creates the virtual display. We wait for it and launch the app asynchronously in background.
    if (newDisplay != null && startApp != null) {
      unawaited(() async {
        try {
          final displayId = await displayCompleter.future.timeout(
            const Duration(seconds: 5),
          );

           // 0. 先强杀该应用进程，确保不存在残留的主屏任务栈，从而让新任务栈完全创建在副屏上
          await _adbService.run([
            '-s',
            deviceId,
            'shell',
            'am',
            'force-stop',
            startApp,
          ]);

          // 1. 解析指定应用的入口 Activity 组件名，以保证能精确启动
          String? component;
          final resolveRes = await _adbService.run([
            '-s',
            deviceId,
            'shell',
            'cmd',
            'package',
            'resolve-activity',
            '--brief',
            startApp,
          ]);
          if (resolveRes.isSuccess) {
            final lines = resolveRes.stdout.split('\n');
            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.contains('/') && trimmed.contains(startApp)) {
                component = trimmed;
                break;
              }
            }
          }

          // 2. 运行 am start 在虚拟副屏上以新任务栈模式启动应用
          if (component != null) {
            await _adbService.run([
              '-s',
              deviceId,
              'shell',
              'am',
              'start',
              '-n',
              component,
              '--display',
              displayId.toString(),
              '-f',
              '0x10000000', // FLAG_ACTIVITY_NEW_TASK
            ]);
          } else {
            // 降级使用通用 Intent 启动
            await _adbService.run([
              '-s',
              deviceId,
              'shell',
              'am',
              'start',
              '-a',
              'android.intent.action.MAIN',
              '-c',
              'android.intent.category.LAUNCHER',
              '-p',
              startApp,
              '--display',
              displayId.toString(),
              '-f',
              '0x10000000', // FLAG_ACTIVITY_NEW_TASK
            ]);
          }

          // 3. 启动后台守护轮询，防范 Activity 在跳转时逃逸回主屏幕（Display 0）
          // 轮询持续 12 秒，每 500 毫秒检查一次，主要覆盖开屏广告与主页面过渡期
          _startActivityEscapeGuardian(deviceId, startApp, displayId);
        } catch (e) {
          stdout.write('[scrcpy-server error] Failed to launch app on virtual display: $e\n');
        }
      }());
    }

    return textureId;
  }

  void _startActivityEscapeGuardian(String deviceId, String packageName, int targetDisplayId) {
    int count = 0;
    Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      count++;
      if (count > 24) { // 12 seconds
        timer.cancel();
        return;
      }
      
      try {
        final res = await _adbService.run([
          '-s',
          deviceId,
          'shell',
          'am',
          'stack',
          'list',
        ]);
        if (!res.isSuccess) return;
        
        final lines = res.stdout.split('\n');
        String? currentStackId;
        String? currentDisplayId;
        
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('Stack id=')) {
            final stackMatch = RegExp(r'Stack id=(\d+)').firstMatch(trimmed);
            final displayMatch = RegExp(r'displayId=(\d+)').firstMatch(trimmed);
            if (stackMatch != null) {
              currentStackId = stackMatch.group(1);
            } else {
              currentStackId = null;
            }
            if (displayMatch != null) {
              currentDisplayId = displayMatch.group(1);
            } else {
              currentDisplayId = null;
            }
          } else if (trimmed.startsWith('taskId=')) {
            if (currentStackId != null && currentDisplayId == '0') {
              if (trimmed.contains(packageName)) {
                final moveRes = await _adbService.run([
                  '-s',
                  deviceId,
                  'shell',
                  'am',
                  'display',
                  'move-stack',
                  currentStackId,
                  targetDisplayId.toString(),
                ]);
                if (moveRes.isSuccess) {
                  stdout.write('[EscapeGuardian] Successfully moved escaped stack $currentStackId of $packageName back to display $targetDisplayId\n');
                }
                break;
              }
            }
          }
        }
      } catch (e) {
        // Ignored
      }
    });
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
    await _adbService.run([
      '-s',
      deviceId,
      'forward',
      '--remove',
      'tcp:${session.port}',
    ]);
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
    final textureId = ref.watch(embeddedScrcpyServiceProvider).getTextureId(deviceId);
    if (textureId != null) {
      // 避免在 build 中直接修改 state 或进行副作用，使用 microtask 延迟注册进程监听
      Future.microtask(() => _listenToProcessExit(textureId));
    }
    return textureId;
  }

  void _listenToProcessExit(int textureId) {
    final service = ref.read(embeddedScrcpyServiceProvider);
    final process = service.getServerProcess(deviceId);
    process?.exitCode.then((code) {
      // 如果当前的投屏状态依然是这个 textureId，且进程已退出，说明是连接断开，自动执行清理
      if (state == textureId) {
        service.stop(deviceId);
        state = null;
      }
    });
  }

  Future<void> toggleMirroring({String? newDisplay, String? startApp}) async {
    final service = ref.read(embeddedScrcpyServiceProvider);
    if (service.isActive(deviceId)) {
      await service.stop(deviceId);
      ref.read(screenPowerOffProvider(deviceId).notifier).setOff(false);
      state = null;
    } else {
      try {
        final textureId = await service.start(
          deviceId: deviceId,
          newDisplay: newDisplay,
          startApp: startApp,
        );
        state = textureId;
        _listenToProcessExit(textureId);
      } catch (e) {
        state = null;
        rethrow;
      }
    }
  }

  Future<void> restartMirroring({String? newDisplay, String? startApp}) async {
    final service = ref.read(embeddedScrcpyServiceProvider);
    if (service.isActive(deviceId)) {
      await service.stop(deviceId);
      ref.read(screenPowerOffProvider(deviceId).notifier).setOff(false);
      state = null;
      // 稍作延迟确保资源完全释放
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    try {
      final textureId = await service.start(
        deviceId: deviceId,
        newDisplay: newDisplay,
        startApp: startApp,
      );
      state = textureId;
      _listenToProcessExit(textureId);
    } catch (e) {
      state = null;
      rethrow;
    }
  }

  Future<void> forceStop() async {
    final service = ref.read(embeddedScrcpyServiceProvider);
    if (service.isActive(deviceId)) {
      await service.stop(deviceId);
      ref.read(screenPowerOffProvider(deviceId).notifier).setOff(false);
      state = null;
    }
  }
}

final activeEmbeddedMirrorProvider =
    NotifierProvider.family<ActiveEmbeddedMirrorNotifier, int?, String>(
      ActiveEmbeddedMirrorNotifier.new,
    );
