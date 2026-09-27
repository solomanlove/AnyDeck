import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../adb/adb_service.dart';
import '../providers/app_providers.dart';
import 'app_virtual_display_launcher.dart';
import 'rust_device_bridge.dart';
import 'scrcpy_camera_options.dart';

part 'embedded_scrcpy_providers.dart';

class EmbeddedScrcpySession {
  EmbeddedScrcpySession({
    required this.deviceId,
    required this.port,
    required this.serverProcess,
    required this.textureId,
    required this.rustHandle,
    required this.startedAt,
    this.camera,
  });

  final String deviceId;
  final int port;
  final Process serverProcess;
  final int textureId;
  final int rustHandle;
  final DateTime startedAt;
  final ScrcpyCameraOptions? camera;
}

class EmbeddedScrcpyService {
  EmbeddedScrcpyService(this._adbService, [RustDeviceBridge? bridge])
      : _bridge = bridge ?? RustDeviceBridge.instance;

  final AdbService _adbService;
  final RustDeviceBridge _bridge;
  final Map<String, EmbeddedScrcpySession> _sessions = {};
  static const _textures = MethodChannel('anydeck/rust_texture');

  bool isActive(String deviceId) => _sessions.containsKey(deviceId);
  int? getTextureId(String deviceId) => _sessions[deviceId]?.textureId;
  int? getRustHandle(String deviceId) => _sessions[deviceId]?.rustHandle;
  Process? getServerProcess(String deviceId) => _sessions[deviceId]?.serverProcess;

  /// 获取指定已连接镜像的视频帧尺寸。
  Map<String, int>? getVideoSize(String deviceId) {
    final session = _sessions[deviceId];
    if (session == null) return null;
    final size = _bridge.videoSize(session.rustHandle);
    final width = size >> 32;
    final height = size & 0xffffffff;
    if (width == 0 || height == 0) return null;
    return {'width': width, 'height': height};
  }

  /// 向指定设备的 control socket 发送控制二进制报文。
  Future<bool> sendControl({
    required String deviceId,
    required Uint8List controlMessage,
  }) async {
    final session = _sessions[deviceId];
    if (session == null) return false;
    return _bridge.sendControl(
      session.rustHandle,
      controlMessage,
    );
  }

  /// 提取匹配版本的内置 server，供投屏与独立音频/剪贴板会话复用。
  Future<String> extractScrcpyServerJar() async {
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
    ScrcpyCameraOptions? camera,
  }) async {
    if (camera != null && (newDisplay != null || startApp != null)) {
      throw ArgumentError('Camera cannot create a display or launch an app');
    }
    final sessionId = camera?.sessionId ?? deviceId;
    camera?.checkActive();
    if (_sessions.containsKey(sessionId)) {
      return _sessions[sessionId]!.textureId;
    }
    final scid = camera?.scid ??
        (Random.secure().nextInt(0x7ffffffe) + 1).toRadixString(16);
    final socketName = camera?.socketName ?? 'scrcpy_${scid.padLeft(8, '0')}';

    // 1. Resolve and push scrcpy-server.jar
    final serverJar = await extractScrcpyServerJar();
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

    camera?.checkActive();

    // 2. Allocate free port and setup forward tunnel
    final localPort = await _findFreePort();
    final forwardRes = await _adbService.run([
      '-s',
      deviceId,
      'forward',
      'tcp:$localPort',
      'localabstract:$socketName',
    ]);
    if (!forwardRes.isSuccess) {
      throw Exception('Failed to setup adb forward: ${forwardRes.stderr}');
    }
    if (camera != null) {
      bool removed = false;
      camera.removeForward = () async {
        if (removed) return;
        removed = true;
        await _adbService.run(['-s', deviceId, 'forward', '--remove', 'tcp:$localPort']);
      };
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
    if (camera != null && sdkVersion < 31) {
      await camera.removeForward?.call();
      throw CameraPreviewException(sdkVersion == 0 ? 'cameraStartFailed' : 'cameraAndroidRequired');
    }
    final bool isAudioSupported = sdkVersion >= 30; // Android 11+ (API 30+)

    // 确保从 SharedPreferences 中获取最新的设置，防止 Isolate 异步加载延迟
    final prefs = await SharedPreferences.getInstance();
    // scrcpy 音频是设备级采集，并非虚拟副屏/App 级采集；单 App 窗口关闭音频，避免与整机投屏产生重音。
    final bool mirrorAudioEnabled =
        camera == null &&
        startApp == null &&
        (prefs.getBool('settings.mirrorAudioEnabled') ?? true) &&
        isAudioSupported;
    final int bitrate = camera != null ? 4000000 : prefs.getInt('settings.mirrorVideoBitrate') ?? 8000000;
    final int maxSize = camera != null ? 1280 : prefs.getInt('settings.mirrorMaxSize') ?? 1080;

    // 若设备当前处于休眠或息屏状态，发送 KEYCODE_WAKEUP (224) 唤醒屏幕以确保 SurfaceFlinger 正常产出渲染帧
    if (camera == null) {
      unawaited(_adbService.shellArgs(deviceId, ['input', 'keyevent', '224']));
    }

    // 3. Start scrcpy-server process on Android
    Process serverProcess;
    try {
      camera?.checkActive();
      serverProcess = await _adbService.start([
        '-s',
        deviceId,
        'shell',
        'CLASSPATH=/data/local/tmp/scrcpy-server.jar',
        'app_process',
        '/',
        'com.genymobile.scrcpy.Server',
        '4.0',
        'scid=$scid',
        'log_level=verbose',
        'audio=${mirrorAudioEnabled ? "true" : "false"}',
        if (mirrorAudioEnabled) 'audio_codec=raw',
        'video_codec=h264',
        'video_bit_rate=$bitrate',
        if (maxSize > 0) 'max_size=$maxSize',
        if (camera == null) 'stay_awake=true',
        // 原生客户端固定连接 video/control，摄像头页不发送触控或键盘消息。
        'control=true',
        'tunnel_forward=true',
        if (camera != null)
          ...camera.serverArguments
        else if (newDisplay != null) ...[
          'new_display=$newDisplay',
          'vd_destroy_content=true',
          'vd_system_decorations=false',
        ] else
          'display_id=0',
      ]);
      camera?.attach(serverProcess);
    } catch (_) {
      if (camera != null) {
        await camera.removeForward?.call();
      } else {
        await _adbService.run(['-s', deviceId, 'forward', '--remove', 'tcp:$localPort']);
      }
      rethrow;
    }

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

    // 4. Connect via Pure Rust VideoToolbox & AudioQueue
    int textureId = 0;
    int rustHandle = 0;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      camera?.checkActive();
      rustHandle = _bridge.startMirror(
        '127.0.0.1',
        localPort,
        mirrorAudioEnabled,
      );
      if (rustHandle == 0) {
        throw Exception('Failed to start Rust mirror session');
      }

      // 空虚拟副屏不会产生视频首帧；先启动 App，再等待 Rust/VideoToolbox 可渲染首帧。
      if (newDisplay != null && startApp != null) {
        await launchAppOnVirtualDisplay(
          adbService: _adbService,
          deviceId: deviceId,
          packageName: startApp,
          displayIdFuture: displayCompleter.future,
        );
      }

      // 等待 Rust 核心建立连接并进入就绪状态
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (_bridge.status(rustHandle) == 0) {
        camera?.checkActive();
        if (DateTime.now().isAfter(deadline)) {
          throw Exception('Rust mirror session connection timed out');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (_bridge.status(rustHandle) >= 2) {
        throw Exception('Rust mirror session failed to connect');
      }

      // 注册至 Swift RustTexturePlugin 获得 Metal/TextureId
      await _textures.invokeMethod<void>('track', {'handle': rustHandle});
      final registered = await _textures.invokeMethod<int>('register', {
        'handle': rustHandle,
      });
      if (registered == null) {
        throw Exception('Failed to register Flutter texture for handle $rustHandle');
      }
      textureId = registered;
      camera?.checkActive();

      final session = EmbeddedScrcpySession(
        deviceId: deviceId,
        port: localPort,
        serverProcess: serverProcess,
        textureId: textureId,
        rustHandle: rustHandle,
        startedAt: DateTime.now(),
        camera: camera,
      );

      _sessions[sessionId] = session;
    } catch (e) {
      // Cleanup on failure
      camera?.cancel();
      if (rustHandle != 0) {
        try {
          await _textures.invokeMethod<void>('untrack', {'handle': rustHandle});
          if (textureId != 0) {
            await _textures.invokeMethod<void>('unregister', {'textureId': textureId});
          }
        } catch (_) {}
        _bridge.stop(rustHandle);
        _bridge.release(rustHandle);
      }
      serverProcess.kill();
      if (camera != null) {
        await camera.removeForward?.call();
      } else {
        await _adbService.run([
          '-s',
          deviceId,
          'forward',
          '--remove',
          'tcp:$localPort',
        ]);
      }
      rethrow;
    }

    return textureId;
  }


  Future<void> stop(String deviceId) async {
    final session = _sessions.remove(deviceId);
    if (session == null) return;

    try {
      await _textures.invokeMethod<void>('untrack', {'handle': session.rustHandle});
      await _textures.invokeMethod<void>('unregister', {'textureId': session.textureId});
    } catch (e) {
      // Ignored during stop
    }

    _bridge.stop(session.rustHandle);
    _bridge.release(session.rustHandle);

    session.serverProcess.kill();
    if (session.camera != null) {
      await session.camera!.removeForward?.call();
    } else {
      await _adbService.run([
        '-s',
        session.deviceId,
        'forward',
        '--remove',
        'tcp:${session.port}',
      ]);
    }
  }

  void stopAll() {
    final deviceIds = List<String>.from(_sessions.keys);
    for (final id in deviceIds) {
      stop(id);
    }
  }
}
