import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:isolate';
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

typedef _AirplaySetAudioEnabledNative = Void Function(Uint8);
typedef _AirplaySetAudioEnabledDart = void Function(int);

/// AirPlay Server 服务状态 Notifier
class AirPlayServerNotifier extends Notifier<AirPlaySessionData?> {
  Timer? _timer;
  final Map<int, String> _lastErrors = {};
  bool _spawningStandby = false;
  static const int _initialClientSlots = 3;
  static const int _maxConcurrentSessions = 4;

  @override
  AirPlaySessionData? build() {
    AirPlaySessionData? latestSession;
    listenSelf((_, next) => latestSession = next);
    ref.onDispose(() {
      _timer?.cancel();
      final current = latestSession;
      if (current != null) {
        for (final s in current.allSessions) {
          unawaited(AirPlayServerService.instance.stop(s));
        }
      }
    });
    return null;
  }

  /// 开启投屏服务（仅主槽位发布单个 Bonjour 广播，附加槽位用于多设备并发解码渲染）
  Future<void> startServer({
    String name = 'AnyDeck-AirPlay',
    int rtspPort = 7000,
    int videoPort = 7100,
  }) async {
    await stopServer();
    final service = AirPlayServerService.instance;
    final primary = await service.start(
      name: name,
      rtspPort: rtspPort,
      videoPort: videoPort,
    );
    final standbySlots = <AirPlaySessionData>[];
    for (int i = 1; i < _initialClientSlots; i++) {
      try {
        final slot = await service.start(
          name: name,
          rtspPort: 0,
          videoPort: 0,
        );
        standbySlots.add(slot);
      } catch (e) {
        debugPrint('[AirPlay] Pre-allocated slot #$i skipped: $e');
      }
    }
    state = primary.copyWith(additionalSessions: standbySlots);
    _lastErrors.clear();

    // 启动状态、客户端元数据与画面尺寸轮询
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      _pollAllSessions();
    });
  }

  void _pollAllSessions() {
    final current = state;
    if (current == null) return;
    final service = AirPlayServerService.instance;
    final all = current.allSessions;
    bool changed = false;
    final updatedList = <AirPlaySessionData>[];

    for (final session in all) {
      final error = service.getLastError(session.id);
      if (error != null && error != _lastErrors[session.id]) {
        _lastErrors[session.id] = error;
        debugPrint('[AirPlay] ERROR (${session.id}): $error');
      }
      final status = service.getStatus(session.id);
      final size = service.getDimensions(session.id);
      final client = service.getClientInfo(session.id);
      final isMirroring = status == AirPlayServerStatus.mirroring;

      final nextW = isMirroring ? (size?.width.toInt() ?? session.width) : 0;
      final nextH = isMirroring ? (size?.height.toInt() ?? session.height) : 0;
      final nextDevId = isMirroring
          ? (client?.deviceId ?? session.clientDeviceId)
          : client?.deviceId;
      final nextModel = isMirroring
          ? (client?.model ?? session.clientModel)
          : client?.model;
      final nextName = isMirroring
          ? (client?.name ?? session.clientName)
          : client?.name;

      if (status != session.status ||
          nextW != session.width ||
          nextH != session.height ||
          nextDevId != session.clientDeviceId ||
          nextModel != session.clientModel ||
          nextName != session.clientName) {
        changed = true;
        updatedList.add(
          session.copyWith(
            status: status,
            width: nextW,
            height: nextH,
            clientDeviceId: nextDevId,
            clientModel: nextModel,
            clientName: nextName,
            clearClient: !isMirroring && client == null,
            additionalSessions: const [],
          ),
        );
      } else {
        updatedList.add(session.copyWith(additionalSessions: const []));
      }
    }

    if (changed && updatedList.isNotEmpty) {
      state = updatedList.first.copyWith(
        additionalSessions: updatedList.sublist(1),
      );
    }

    // 多台设备并发投屏支持：当所有已分配槽位均处于投屏状态时，自动补充一个无广播待机槽位
    final latest = state;
    if (latest != null &&
        !_spawningStandby &&
        latest.allSessions.length < _maxConcurrentSessions &&
        latest.allSessions.every((s) => s.status == AirPlayServerStatus.mirroring)) {
      _spawningStandby = true;
      final slot = latest.allSessions.length + 1;
      unawaited(_spawnStandbySession(slot));
    }
  }

  Future<void> _spawnStandbySession(int slot) async {
    try {
      final baseName = (state?.serverName.trim().isNotEmpty ?? false)
          ? state!.serverName.trim()
          : 'AnyDeck-AirPlay';
      final standby = await AirPlayServerService.instance.start(
        name: baseName,
        rtspPort: 0,
        videoPort: 0,
      );
      final current = state;
      if (current == null) {
        await AirPlayServerService.instance.stop(standby);
        return;
      }
      state = current.copyWith(
        additionalSessions: [...current.additionalSessions, standby],
      );
    } catch (e) {
      debugPrint('[AirPlay] Standby session #$slot spawn skipped: $e');
    } finally {
      _spawningStandby = false;
    }
  }

  /// 断开单台设备的 AirPlay 投屏会话（保持主广播接收器与其他正在投屏的设备继续运行）
  Future<void> stopSession(int sessionId) async {
    final current = state;
    if (current == null) return;
    final all = current.allSessions;
    final target = all.where((s) => s.id == sessionId).firstOrNull;
    if (target == null) return;

    await AirPlayServerService.instance.disconnect(sessionId);
    _lastErrors.remove(sessionId);

    final updated = all.map((s) {
      if (s.id == sessionId) {
        return s.copyWith(
          status: AirPlayServerStatus.idle,
          width: 0,
          height: 0,
          clearClient: true,
          additionalSessions: const [],
        );
      }
      return s.copyWith(additionalSessions: const []);
    }).toList();

    state = updated.first.copyWith(
      additionalSessions: updated.sublist(1),
    );
  }

  /// 停止全部投屏服务
  Future<void> stopServer() async {
    _timer?.cancel();
    _timer = null;
    _lastErrors.clear();
    final current = state;
    if (current != null) {
      for (final s in current.allSessions) {
        await AirPlayServerService.instance.stop(s);
      }
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

  late final _AirplayStatusDart _statusFunc;
  late final _AirplayDimensionsDart _dimFunc;

  _AirplayErrorDart? _errorFunc;
  _AirplayErrorDart? _clientInfoFunc;
  _AirplaySetAudioEnabledDart? _setAudioEnabledFunc;
  bool _audioEnabled = true;

  bool _initialized = false;
  bool get isSupported => Platform.isMacOS && _initialized;

  void _initFfi() {
    try {
      _lib = RustDeviceBridge.instance.library;
      _lib!.lookupFunction<_AirplayStartNative, _AirplayStartDart>(
        'anydeck_airplay_start',
      );
      _lib!.lookupFunction<_AirplayStopNative, _AirplayStopDart>(
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
      try {
        _clientInfoFunc = _lib!.lookupFunction<_AirplayErrorNative, _AirplayErrorDart>(
          'anydeck_airplay_copy_client_info',
        );
      } catch (_) {}
      try {
        _setAudioEnabledFunc = _lib!
            .lookupFunction<_AirplaySetAudioEnabledNative, _AirplaySetAudioEnabledDart>(
              'anydeck_airplay_set_audio_enabled',
            );
      } catch (_) {}
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }

  /// 动态切换 AirPlay 音频转发开关（实时静音/恢复 AudioQueue 输出）
  void setAudioEnabled(bool enabled) {
    _audioEnabled = enabled;
    _setAudioEnabledFunc?.call(enabled ? 1 : 0);
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
    _setAudioEnabledFunc?.call(_audioEnabled ? 1 : 0);

    // native 启动包含密钥文件、Bonjour 和监听初始化，放到后台 Isolate。
    final handle = await Isolate.run(
      () => _startNativeAirPlay(name, rtspPort, videoPort),
    );
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

  /// 读取当前连接的 AirPlay 客户端设备标识、内部型号与名称。
  ({String? deviceId, String? model, String? name})? getClientInfo(int handle) {
    final readClient = _clientInfoFunc;
    if (readClient == null) return null;
    final buffer = calloc<Uint8>(1024);
    try {
      final length = readClient(handle, buffer, 1024);
      if (length <= 0 || length > 1024) return null;
      final raw = utf8.decode(buffer.asTypedList(length), allowMalformed: true);
      final parts = raw.split('\t');
      if (parts.length < 3) return null;
      final devId = parts[0].trim();
      final model = parts[1].trim();
      final name = parts[2].trim();
      return (
        deviceId: devId.isEmpty ? null : devId,
        model: model.isEmpty ? null : model,
        name: name.isEmpty ? null : name,
      );
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

  /// 仅断开单个客户端槽位的 AirPlay 投屏连接，保留主广播与纹理槽位供后续连接复用
  Future<void> disconnect(int handle) async {
    if (!_initialized) return;
    await Isolate.run(() => _disconnectNativeAirPlay(handle));
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
    final handle = session.id;
    // UxPlay stop 会 join 协议线程，不能阻塞 Flutter UI 线程。
    await Isolate.run(() => _stopNativeAirPlay(handle));
  }
}

/// 在通用 iOS 投屏窗口中显示 AirPlay，不再创建专用 AirPlay 窗口。
///
/// [deviceId] 可关联已打开的 USB 投屏窗口；缺失时使用会话级稳定标识。
Future<void> openAirPlayMirrorWindow(
  AirPlaySessionData session, {
  String? deviceId,
  String? deviceName,
}) async {
  final double aspect = (session.width > 0 && session.height > 0)
      ? (session.width / session.height)
      : (9.0 / 19.5);
  final resolvedDeviceId = deviceId ?? 'airplay-${session.id}';
  final resolvedDeviceName = deviceName ?? session.clientName ?? 'iPhone';
  final initialSize = resolveMirrorInitialWindowSize(null, ratio: aspect);

  try {
    await createAdbManageWindow(
      arguments: {
        'type': 'mirror',
        'deviceId': resolvedDeviceId,
        'deviceName': resolvedDeviceName,
        'isIos': true,
        'airplayHandle': session.id,
        'airplayAspectRatio': aspect,
      },
      frame: Offset.zero & initialSize,
      title: '$resolvedDeviceName · AirPlay',
    );
  } catch (e) {
    debugPrint('[AirPlay] Failed to open mirror window: $e');
  }
}

/// 后台 Isolate 独立加载同一路径的动态库，复用进程内 Rust 会话表。
int _startNativeAirPlay(String name, int rtspPort, int videoPort) {
  final start = RustDeviceBridge.instance.library
      .lookupFunction<_AirplayStartNative, _AirplayStartDart>('anydeck_airplay_start');
  final cName = utf8.encode('$name\x00');
  final namePtr = calloc<Uint8>(cName.length);
  try {
    namePtr.asTypedList(cName.length).setAll(0, cName);
    return start(namePtr, rtspPort, videoPort);
  } finally {
    calloc.free(namePtr);
  }
}

/// 断开指定客户端槽位的活跃连接。
void _disconnectNativeAirPlay(int handle) {
  try {
    final disconnect = RustDeviceBridge.instance.library
        .lookupFunction<_AirplayStopNative, _AirplayStopDart>(
          'anydeck_airplay_disconnect',
        );
    disconnect(handle);
  } catch (_) {}
}

/// 等 native 线程退出后才完成 Future，支持顺序停止并重启服务。
void _stopNativeAirPlay(int handle) {
  final stop = RustDeviceBridge.instance.library
      .lookupFunction<_AirplayStopNative, _AirplayStopDart>('anydeck_airplay_stop');
  stop(handle);
}
