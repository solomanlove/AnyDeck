import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/window/multi_window_compat.dart';
import '../scrcpy/rust_device_bridge.dart';
import 'airplay_server_state.dart';

typedef _AirplayStartNative = Uint64 Function(Pointer<Uint8>, Uint16, Uint16);
typedef _AirplayStartDart = int Function(Pointer<Uint8>, int, int);

typedef _AirplayStopNative = Void Function(Uint64);
typedef _AirplayStopDart = void Function(int);

typedef _AirplayStatusNative = Uint8 Function(Uint64);
typedef _AirplayStatusDart = int Function(int);

typedef _AirplayDimensionsNative =
    Uint8 Function(Uint64, Pointer<Uint32>, Pointer<Uint32>);
typedef _AirplayDimensionsDart = int Function(int, Pointer<Uint32>, Pointer<Uint32>);

typedef _AirplayErrorNative = UintPtr Function(Uint64, Pointer<Uint8>, UintPtr);
typedef _AirplayErrorDart = int Function(int, Pointer<Uint8>, int);

/// AirPlay Server 服务状态 Notifier
class AirPlayServerNotifier extends Notifier<AirPlaySessionData?> {
  Timer? _timer;
  String? _lastError;

  @override
  AirPlaySessionData? build() {
    ref.onDispose(() {
      _timer?.cancel();
      final current = state;
      if (current != null) {
        unawaited(AirPlayServerService.instance.stop(current));
      }
    });
    return null;
  }

  /// 开启投屏服务
  Future<void> startServer({
    String name = 'AnyDeck-AirPlay',
    int rtspPort = 7000,
    int videoPort = 7100,
  }) async {
    await stopServer();
    final service = AirPlayServerService.instance;
    final session = await service.start(
      name: name,
      rtspPort: rtspPort,
      videoPort: videoPort,
    );
    state = session;
    _lastError = null;

    // 启动状态与画面尺寸轮询
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      final current = state;
      if (current == null) return;

      final error = service.getLastError(current.id);
      if (error != null && error != _lastError) {
        _lastError = error;
        debugPrint('[AirPlay] ERROR: $error');
      }
      final status = service.getStatus(current.id);
      final size = service.getDimensions(current.id);

      if (status != current.status ||
          (size != null &&
              (size.width.toInt() != current.width ||
                  size.height.toInt() != current.height))) {
        state = current.copyWith(
          status: status,
          width: size?.width.toInt() ?? current.width,
          height: size?.height.toInt() ?? current.height,
        );
      }
    });
  }

  /// 停止投屏服务
  Future<void> stopServer() async {
    _timer?.cancel();
    _timer = null;
    final current = state;
    if (current != null) {
      await AirPlayServerService.instance.stop(current);
      state = null;
    }
  }
}

/// AirPlay Server 服务全局状态 Provider
final airplaySessionProvider =
    NotifierProvider<AirPlayServerNotifier, AirPlaySessionData?>(
  AirPlayServerNotifier.new,
);

/// AirPlay 屏幕镜像服务核心单例
/// 负责调度 Rust 内部的 AirPlay 服务端并注册 Flutter External Texture。
class AirPlayServerService {
  AirPlayServerService._() {
    _initFfi();
  }

  static final instance = AirPlayServerService._();

  static const _channel = MethodChannel('anydeck/rust_texture');
  DynamicLibrary? _lib;

  late final _AirplayStartDart _startFunc;
  late final _AirplayStopDart _stopFunc;
  late final _AirplayStatusDart _statusFunc;
  late final _AirplayDimensionsDart _dimFunc;

  _AirplayErrorDart? _errorFunc;

  bool _initialized = false;
  bool get isSupported => Platform.isMacOS && _initialized;

  void _initFfi() {
    try {
      _lib = RustDeviceBridge.instance.library;
      _startFunc = _lib!.lookupFunction<_AirplayStartNative, _AirplayStartDart>(
        'anydeck_airplay_start',
      );
      _stopFunc = _lib!.lookupFunction<_AirplayStopNative, _AirplayStopDart>(
        'anydeck_airplay_stop',
      );
      _statusFunc = _lib!.lookupFunction<_AirplayStatusNative, _AirplayStatusDart>(
        'anydeck_airplay_get_status',
      );
      _dimFunc = _lib!.lookupFunction<
        _AirplayDimensionsNative,
        _AirplayDimensionsDart
      >('anydeck_airplay_get_dimensions');
      // 兼容尚未重新构建、没有诊断符号的旧动态库。
      try {
        _errorFunc = _lib!.lookupFunction<_AirplayErrorNative, _AirplayErrorDart>(
          'anydeck_airplay_copy_last_error',
        );
      } catch (_) {}
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  /// 启动 AirPlay 屏幕镜像服务广播与接收
  /// - [name]: 在 iOS 控制中心屏幕镜像列表中展示的名称
  /// - [rtspPort]: RTSP 信令端口，默认 7000
  /// - [videoPort]: 视频数据流接收端口，默认 7100
  Future<AirPlaySessionData> start({
    String name = 'AnyDeck-AirPlay',
    int rtspPort = 7000,
    int videoPort = 7100,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('AirPlay Server 仅支持 macOS 平台且需动态库支持');
    }

    final cName = utf8.encode('$name\x00');
    final namePtr = calloc<Uint8>(cName.length);
    namePtr.asTypedList(cName.length).setAll(0, cName);

    try {
      final handle = _startFunc(namePtr, rtspPort, videoPort);
      if (handle == 0) {
        throw StateError('启动 AirPlay Server 失败');
      }

      // 注册至 macOS Texture Registry 获取纹理 ID
      int? textureId;
      try {
        await _channel.invokeMethod<void>('track', {'handle': handle});
        textureId = await _channel.invokeMethod<int>('register', {
          'handle': handle,
        });
      } catch (_) {}

      return AirPlaySessionData(
        id: handle,
        serverName: name,
        rtspPort: rtspPort,
        videoPort: videoPort,
        status: AirPlayServerStatus.idle,
        textureId: textureId,
      );
    } finally {
      calloc.free(namePtr);
    }
  }

  /// 获取当前投屏分辨率
  Size? getDimensions(int handle) {
    if (!_initialized) return null;
    final wPtr = calloc<Uint32>();
    final hPtr = calloc<Uint32>();
    try {
      final ok = _dimFunc(handle, wPtr, hPtr);
      if (ok != 0 && wPtr.value > 0 && hPtr.value > 0) {
        return Size(wPtr.value.toDouble(), hPtr.value.toDouble());
      }
      return null;
    } finally {
      calloc.free(wPtr);
      calloc.free(hPtr);
    }
  }

  /// 读取有界原生错误，让现有本地日志导出包含协议失败原因。
  String? getLastError(int handle) {
    final readError = _errorFunc;
    if (readError == null) return null;
    final buffer = calloc<Uint8>(2048);
    try {
      final length = readError(handle, buffer, 2048);
      if (length <= 0 || length > 2048) return null;
      return utf8.decode(buffer.asTypedList(length), allowMalformed: true);
    } finally {
      calloc.free(buffer);
    }
  }

  /// 获取当前服务运行状态
  AirPlayServerStatus getStatus(int handle) {
    if (!_initialized) return AirPlayServerStatus.stopped;
    final code = _statusFunc(handle);
    return AirPlayServerStatus.fromRaw(code);
  }

  /// 停止 AirPlay 服务并注销纹理
  Future<void> stop(AirPlaySessionData session) async {
    if (!_initialized) return;
    if (session.textureId != null) {
      try {
        await _channel.invokeMethod<void>('unregister', {
          'textureId': session.textureId,
        });
      } catch (_) {}
    }
    try {
      await _channel.invokeMethod<void>('untrack', {'handle': session.id});
    } catch (_) {}
    _stopFunc(session.id);
  }
}

/// 打开或重新打开 AirPlay 独立非全屏等比投屏窗口。
///
/// 当用户在手机端开启屏幕镜像，或在电脑端需要重新唤出投屏小窗口时调用。
Future<void> openAirPlayMirrorWindow(AirPlaySessionData session) async {
  final double aspect = (session.width > 0 && session.height > 0)
      ? (session.width / session.height)
      : (9.0 / 19.5);
  final double windowWidth = aspect < 1.0 ? 360.0 : 720.0;
  final double windowHeight = windowWidth / aspect;
  final initialSize = Size(windowWidth, windowHeight);

  try {
    await createAdbManageWindow(
      arguments: {
        'type': 'airplay_mirror',
        'handle': session.id,
        'aspectRatio': aspect,
        'deviceName': session.clientName ?? 'iPhone',
      },
      frame: Offset.zero & initialSize,
      title: '${session.clientName ?? 'iPhone'} - AirPlay',
    );
  } catch (e) {
    debugPrint('[AirPlay] Failed to open mirror window: $e');
  }
}
