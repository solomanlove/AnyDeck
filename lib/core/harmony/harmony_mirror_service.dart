import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../scrcpy/rust_device_bridge.dart';
import '../providers/app_providers.dart';
import 'harmony_mirror_session.dart';
import 'hdc_service.dart';

/// 鸿蒙设备镜像（投屏）管理服务，通过本地 Java 桥接进程运行 HOScrcpy。
class HarmonyMirrorService {
  HarmonyMirrorService(this._hdcService);

  final HdcService _hdcService;
  final Map<String, HarmonyMirrorSession> _sessions = {};
  static const _textures = MethodChannel('anydeck/rust_texture');

  /// 投屏流旋转发生时通知 UI 刷新新 Texture
  void Function(String deviceId, int newTextureId)? onMirrorRotated;

  bool isActive(String deviceId) => _sessions.containsKey(deviceId);
  int? getTextureId(String deviceId) => _sessions[deviceId]?.textureId;
  int? getRustHandle(String deviceId) => _sessions[deviceId]?.rustHandle;
  Process? getServerProcess(String deviceId) => _sessions[deviceId]?.serverProcess;

  /// 获取指定已连接鸿蒙镜像的视频帧尺寸。
  Map<String, int>? getVideoSize(String deviceId) {
    final session = _sessions[deviceId];
    if (session == null) return null;
    final size = RustDeviceBridge.instance.videoSize(session.rustHandle);
    final width = size >> 32;
    final height = size & 0xffffffff;
    if (width == 0 || height == 0) return null;
    return {'width': width, 'height': height};
  }

  /// 向指定鸿蒙设备的 control socket 发送控制二进制报文。
  /// 包含双重保障机制：优先走 Rust 投屏 Control Socket 直通通道；
  /// 若 Socket 尚未就绪或发送失败，则自动降级为 HDC uinput 命令执行。
  Future<bool> sendControl({
    required String deviceId,
    required Uint8List controlMessage,
  }) async {
    final session = _sessions[deviceId];
    if (session != null) {
      final sent = RustDeviceBridge.instance.sendControl(
        session.rustHandle,
        controlMessage,
      );
      if (sent) return true;
    }

    // 容灾策略：如果 Rust 控制 Socket 尚未连接或写入失败，通过 HDC uinput 命令执行降级控制
    return _sendFallbackControl(deviceId, controlMessage);
  }

  /// 通过 HDC 注入命令对鸿蒙设备进行兜底触控控制。
  Future<bool> _sendFallbackControl(
    String deviceId,
    Uint8List controlMessage,
  ) async {
    if (controlMessage.length >= 18 && controlMessage[0] == 2) {
      final byteData = ByteData.sublistView(controlMessage);
      final action = byteData.getUint8(1);
      final x = byteData.getUint32(10, Endian.big);
      final y = byteData.getUint32(14, Endian.big);
      // action: 0 = down, 1 = up, 2 = move
      final subcmd = action == 0
          ? '-d $x $y'
          : action == 1
              ? '-u $x $y'
              : '-m $x $y';
      final res = await _hdcService.shell(deviceId, 'uinput -T $subcmd');
      return res.isSuccess;
    }
    return false;
  }

  /// 从 Flutter 资源包释放鸿蒙投屏 Java 桥接 jar 包。
  Future<String> _extractSidecarJar() async {
    final dir = Directory('${Directory.systemTemp.path}/any_deck_hoscrcpy');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/hoscrcpy-sidecar.jar');
    
    try {
      final bytes = await rootBundle.load('assets/scrcpy/hoscrcpy-sidecar.jar');
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
    } catch (e) {
      stdout.writeln('Error: Failed to load hoscrcpy-sidecar.jar from assets: $e');
      rethrow;
    }
    return file.path;
  }

  /// 从 `hidumper -s DisplayManagerService -a -a` 输出中解析主屏幕宽高。
  static (int?, int?) parseDisplayDimensions(String output) {
    int? width;
    int? height;
    for (final rawLine in LineSplitter.split(output)) {
      final line = rawLine.trim();
      final wMatch = RegExp(r'\bwidth:\s*(\d+)', caseSensitive: false).firstMatch(line);
      if (wMatch != null) width = int.tryParse(wMatch.group(1)!);

      final hMatch = RegExp(r'\bheight:\s*(\d+)', caseSensitive: false).firstMatch(line);
      if (hMatch != null) height = int.tryParse(hMatch.group(1)!);

      if (width != null && height != null && width > 0 && height > 0) {
        return (width, height);
      }
    }
    return (null, null);
  }

  /// 启动鸿蒙投屏。
  Future<int> start({
    required String deviceId,
    int? customWidth,
    int? customHeight,
  }) async {
    if (_sessions.containsKey(deviceId)) {
      return _sessions[deviceId]!.textureId;
    }

    final jarPath = await _extractSidecarJar();
    final hdcPath = _hdcService.executable;

    int width = customWidth ?? 1080;
    int height = customHeight ?? 2400;

    if (customWidth == null || customHeight == null) {
      // 优先从 DisplayManagerService 获取当前实时主屏宽高（适配横屏初始启动）
      try {
        final dispResult = await _hdcService.shell(
          deviceId,
          'hidumper -s DisplayManagerService -a -a',
        );
        if (dispResult.isSuccess && dispResult.stdout.isNotEmpty) {
          final (dw, dh) = parseDisplayDimensions(dispResult.stdout);
          if (dw != null && dh != null && dw > 0 && dh > 0) {
            width = dw;
            height = dh;
          }
        }
      } catch (_) {}

      // 若未能获取，回退尝试 RenderService physical resolution
      if (width == 1080 && height == 2400) {
        try {
          final resResult = await _hdcService.shell(
            deviceId,
            'hidumper -s RenderService -a screen',
          );
          if (resResult.isSuccess && resResult.stdout.isNotEmpty) {
            final match = RegExp(
              r'physical resolution=([0-9]+)x([0-9]+)',
            ).firstMatch(resResult.stdout);
            if (match != null) {
              width = int.tryParse(match.group(1) ?? '') ?? 1080;
              height = int.tryParse(match.group(2) ?? '') ?? 2400;
            }
          }
        } catch (_) {}
      }
    }

    // 1. 启动 Java 桥接 TCP Server 进程（由 Java 端直接作为 TCP scrcpy 服务端接收连接）
    final serverProcess = await Process.start('java', [
      '-cp',
      jarPath,
      'Main',
      '--sn',
      deviceId,
      '--hdc',
      hdcPath,
      '--port',
      '0', // 自动分配可用端口
      '--width',
      '$width',
      '--height',
      '$height',
    ]);

    // 读取就绪信息中的 TCP 端口
    final completer = Completer<int>();
    final subscription = serverProcess.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      stdout.writeln('[hoscrcpy-sidecar stdout] $line');
      try {
        if (line.contains('"ready":true')) {
          final data = jsonDecode(line.trim()) as Map<String, dynamic>;
          final port = data['port'] as int;
          completer.complete(port);
        }
      } catch (_) {}
    });

    serverProcess.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      stderr.writeln('[hoscrcpy-sidecar stderr] $line');
    });

    int tcpPort;
    try {
      tcpPort = await completer.future.timeout(const Duration(seconds: 15));
    } catch (e) {
      subscription.cancel();
      serverProcess.kill();
      throw Exception('Failed to start HarmonyOS mirror sidecar: port allocation timeout');
    }
    subscription.cancel();

    // 2. 调用纯 Rust + VideoToolbox 解码并注册至 Swift 原生 Texture
    int textureId = 0;
    int rustHandle = 0;
    try {
      rustHandle = RustDeviceBridge.instance.startMirror(
        '127.0.0.1',
        tcpPort,
        false,
      );
      if (rustHandle == 0) {
        throw Exception('Failed to start Rust mirror session for HarmonyOS');
      }

      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (RustDeviceBridge.instance.status(rustHandle) == 0) {
        if (DateTime.now().isAfter(deadline)) {
          throw Exception('Rust mirror session connection timed out');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (RustDeviceBridge.instance.status(rustHandle) >= 2) {
        throw Exception('Rust mirror session failed to connect');
      }

      await _textures.invokeMethod<void>('track', {'handle': rustHandle});
      final registered = await _textures.invokeMethod<int>('register', {
        'handle': rustHandle,
      });
      if (registered == null) {
        throw Exception('Failed to register Flutter texture for handle $rustHandle');
      }
      textureId = registered;

      final session = HarmonyMirrorSession(
        deviceId: deviceId,
        port: tcpPort,
        serverProcess: serverProcess,
        textureId: textureId,
        rustHandle: rustHandle,
        startedAt: DateTime.now(),
        width: width,
        height: height,
      );

      _sessions[deviceId] = session;
      _startOrientationMonitor(deviceId);
      return textureId;
    } catch (e) {
      if (rustHandle != 0) {
        try {
          await _textures.invokeMethod<void>('untrack', {'handle': rustHandle});
          if (textureId != 0) {
            await _textures.invokeMethod<void>('unregister', {'textureId': textureId});
          }
        } catch (_) {}
        RustDeviceBridge.instance.stop(rustHandle);
        RustDeviceBridge.instance.release(rustHandle);
      }
      serverProcess.kill();
      rethrow;
    }
  }

  /// 启动屏幕方向监控；检测到横竖屏物理旋转时，重启流以适配最新画面尺寸。
  void _startOrientationMonitor(String deviceId) {
    var mismatchCount = 0;
    _sessions[deviceId]?.orientationTimer?.cancel();
    _sessions[deviceId]?.orientationTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (timer) async {
        final session = _sessions[deviceId];
        if (session == null) {
          timer.cancel();
          return;
        }
        try {
          final res = await _hdcService.shell(
            deviceId,
            'hidumper -s DisplayManagerService -a -a',
          );
          if (!res.isSuccess || res.stdout.isEmpty) return;
          final (dispW, dispH) = parseDisplayDimensions(res.stdout);
          if (dispW == null || dispH == null || dispW <= 0 || dispH <= 0) return;

          final displayIsLandscape = dispW >= dispH;
          final videoIsLandscape = session.width >= session.height;

          if (displayIsLandscape != videoIsLandscape) {
            mismatchCount++;
          } else {
            mismatchCount = 0;
          }

          if (mismatchCount >= 2) {
            timer.cancel();
            await restartForDisplayChange(deviceId, width: dispW, height: dispH);
          }
        } catch (_) {}
      },
    );
  }

  /// 当检测到屏幕旋转时，重启流以适配横竖屏物理画面，彻底防止画面拉伸挤压。
  Future<int?> restartForDisplayChange(
    String deviceId, {
    required int width,
    required int height,
  }) async {
    final oldSession = _sessions[deviceId];
    if (oldSession == null) return null;
    oldSession.orientationTimer?.cancel();

    try {
      await _textures.invokeMethod<void>('untrack', {'handle': oldSession.rustHandle});
      await _textures.invokeMethod<void>('unregister', {'textureId': oldSession.textureId});
    } catch (_) {}
    RustDeviceBridge.instance.stop(oldSession.rustHandle);
    RustDeviceBridge.instance.release(oldSession.rustHandle);

    oldSession.serverProcess.kill();
    _sessions.remove(deviceId);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    try {
      final newTextureId = await start(
        deviceId: deviceId,
        customWidth: width,
        customHeight: height,
      );
      onMirrorRotated?.call(deviceId, newTextureId);
      return newTextureId;
    } catch (e) {
      return null;
    }
  }

  /// 停止鸿蒙投屏。
  Future<void> stop(String deviceId) async {
    final session = _sessions.remove(deviceId);
    if (session == null) {
      return;
    }
    session.orientationTimer?.cancel();
    session.orientationTimer = null;

    try {
      await _textures.invokeMethod<void>('untrack', {'handle': session.rustHandle});
      await _textures.invokeMethod<void>('unregister', {'textureId': session.textureId});
    } catch (_) {}

    RustDeviceBridge.instance.stop(session.rustHandle);
    RustDeviceBridge.instance.release(session.rustHandle);

    session.serverProcess.kill();
    await session.serverProcess.exitCode.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        session.serverProcess.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }

  /// 停止全部投屏。
  void stopAll() {
    final deviceIds = List<String>.from(_sessions.keys);
    for (final id in deviceIds) {
      stop(id);
    }
  }
}

/// 鸿蒙设备镜像的 Notifier，供 UI 订阅以感知和切换该设备的投屏状态。
class ActiveHarmonyMirrorNotifier extends Notifier<int?> {
  ActiveHarmonyMirrorNotifier(this.deviceId);

  final String deviceId;

  @override
  int? build() {
    ref.keepAlive();
    final textureId = ref.watch(harmonyMirrorServiceProvider).getTextureId(deviceId);
    if (textureId != null) {
      Future.microtask(() => _listenToProcessExit(textureId));
    }
    return textureId;
  }

  void _listenToProcessExit(int textureId) {
    final service = ref.read(harmonyMirrorServiceProvider);
    final process = service.getServerProcess(deviceId);
    process?.exitCode.then((code) {
      if (state == textureId) {
        service.stop(deviceId);
        state = null;
      }
    });
  }

  /// 开启或关闭鸿蒙设备的投屏
  Future<void> toggleMirroring() async {
    final service = ref.read(harmonyMirrorServiceProvider);
    if (service.isActive(deviceId)) {
      await service.stop(deviceId);
      state = null;
    } else {
      try {
        final textureId = await service.start(
          deviceId: deviceId,
        );
        state = textureId;
        _listenToProcessExit(textureId);
      } catch (e) {
        state = null;
        rethrow;
      }
    }
  }

  /// 强行停止投屏
  Future<void> forceStop() async {
    final service = ref.read(harmonyMirrorServiceProvider);
    if (service.isActive(deviceId)) {
      await service.stop(deviceId);
      state = null;
    }
  }

  /// 重启投屏
  Future<void> restartMirroring() async {
    final service = ref.read(harmonyMirrorServiceProvider);
    if (service.isActive(deviceId)) {
      await service.stop(deviceId);
      state = null;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    try {
      final textureId = await service.start(
        deviceId: deviceId,
      );
      state = textureId;
      _listenToProcessExit(textureId);
    } catch (e) {
      state = null;
      rethrow;
    }
  }
}

final activeHarmonyMirrorProvider =
    NotifierProvider.family<ActiveHarmonyMirrorNotifier, int?, String>(
      ActiveHarmonyMirrorNotifier.new,
    );
