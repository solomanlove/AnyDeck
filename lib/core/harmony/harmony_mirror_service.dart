import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../scrcpy/rust_device_bridge.dart';
import 'hdc_service.dart';
import '../providers/app_providers.dart';

/// 鸿蒙投屏会话实体，记录投屏相关状态和长连接进程。
class HarmonyMirrorSession {
  HarmonyMirrorSession({
    required this.deviceId,
    required this.port,
    required this.serverProcess,
    required this.textureId,
    required this.rustHandle,
    required this.startedAt,
  });

  final String deviceId;
  final int port;
  final Process serverProcess;
  final int textureId;
  final int rustHandle;
  final DateTime startedAt;
}

/// 鸿蒙设备镜像（投屏）管理服务，通过本地 Java 桥接进程运行 HOScrcpy。
class HarmonyMirrorService {
  HarmonyMirrorService(this._hdcService);

  final HdcService _hdcService;
  final Map<String, HarmonyMirrorSession> _sessions = {};
  static const _textures = MethodChannel('anydeck/rust_texture');

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

  /// 启动鸿蒙投屏。
  Future<int> start({
    required String deviceId,
  }) async {
    if (_sessions.containsKey(deviceId)) {
      return _sessions[deviceId]!.textureId;
    }

    final jarPath = await _extractSidecarJar();
    final hdcPath = _hdcService.executable;

    // 获取设备的物理分辨率
    int width = 1080;
    int height = 2400;
    try {
      final resResult = await _hdcService.shell(deviceId, 'hidumper -s RenderService -a screen');
      if (resResult.isSuccess && resResult.stdout.isNotEmpty) {
        final match = RegExp(r'physical resolution=([0-9]+)x([0-9]+)').firstMatch(resResult.stdout);
        if (match != null) {
          width = int.tryParse(match.group(1) ?? '') ?? 1080;
          height = int.tryParse(match.group(2) ?? '') ?? 2400;
        }
      }
    } catch (_) {}

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
      );

      _sessions[deviceId] = session;
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

  /// 停止鸿蒙投屏。
  Future<void> stop(String deviceId) async {
    final session = _sessions.remove(deviceId);
    if (session == null) {
      return;
    }

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
