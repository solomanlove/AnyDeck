import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'host_recording_backend.dart';
import 'rust_recording_api.dart';

/// 独立录制句柄适配：等待真实首帧/音频就绪，停止后等待 Rust 写完文件与清理。
class RustHostRecording implements HostRecordingBackend {
  RustHostRecording({
    required this.adb,
    required this.deviceId,
    required this.path,
    required this.resolveJar,
    RecordingNativeApi Function()? nativeFactory,
    Future<void> Function(String, int)? lifecycle,
    this.startTimeout = const Duration(seconds: 75),
    this.stopTimeout = const Duration(seconds: 70),
  }) : _nativeFactory = nativeFactory ?? RustRecordingApi.new,
       _lifecycle = lifecycle ?? _track;

  final String adb;
  final String deviceId;
  final String path;
  final Future<String> Function() resolveJar;
  final RecordingNativeApi Function() _nativeFactory;
  final Future<void> Function(String, int) _lifecycle;
  final Duration startTimeout;
  final Duration stopTimeout;
  RecordingNativeApi? _native;
  int? _handle;
  bool _cancelled = false;
  Future<void>? _starting;
  Future<void>? _stopping;
  Timer? _poll;
  final _exit = Completer<String?>();
  static const _channel = MethodChannel('anydeck/rust_texture');

  static Future<void> _track(String method, int handle) => _channel
      .invokeMethod<void>(method, {'handle': handle})
      .timeout(const Duration(seconds: 3));

  @override
  Future<String?> get exited => _exit.future;
  @override
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    final deadline = DateTime.now().add(startTimeout);
    try {
      final jar = await resolveJar().timeout(startTimeout);
      if (_cancelled) throw StateError('Recording cancelled');
      final native = _native = _nativeFactory();
      final handle = native.start(adb, deviceId, jar, path);
      if (handle == 0) {
        throw StateError(
          'Native recording unavailable or device already recording',
        );
      }
      _handle = handle;
      await _lifecycle('track', handle);
      while (!_cancelled &&
          native.status(handle) == 0 &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (_cancelled ||
          DateTime.now().isAfter(deadline) ||
          native.status(handle) != 1) {
        final error = native.error(handle);
        throw StateError(
          error.isEmpty ? 'Recording cancelled or startup timed out' : error,
        );
      }
      _poll = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (native.status(handle) >= 2) {
          _poll?.cancel();
          final error = native.error(handle);
          if (error.isNotEmpty) {
            debugPrint('[HostRecording] Recording failed: $error');
          }
          if (!_exit.isCompleted) _exit.complete(error.isEmpty ? null : error);
        }
      });
    } catch (error) {
      debugPrint('[HostRecording] Start failed: $error');
      cancel();
      // 不等待自己的 _starting，避免启动失败清理形成环形等待。
      await _cleanup();
      if (!_exit.isCompleted) _exit.complete('$error');
      rethrow;
    }
  }

  @override
  void cancel() {
    _cancelled = true;
    _poll?.cancel();
    final handle = _handle;
    if (handle != null) _native!.stop(handle);
  }

  @override
  Future<void> stop() => _stopping ??= _stop();
  Future<void> _stop() async {
    cancel();
    try {
      await _starting;
    } catch (_) {
      /* 启动失败已清理。 */
    }
    final error = await _cleanup();
    if (error != null) {
      debugPrint('[HostRecording] Stop failed: $error');
      throw StateError(error);
    }
  }

  Future<String?> _cleanup() async {
    final handle = _handle;
    if (handle == null) return null;
    final native = _native!;
    final deadline = DateTime.now().add(stopTimeout);
    while (native.status(handle) < 2 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final status = native.status(handle);
    final detail = native.error(handle);
    final error = status < 2
        ? 'Recording finalization timed out'
        : status == 3
        ? (detail.isEmpty ? 'Recording failed' : detail)
        : null;
    native.release(handle);
    _handle = null;
    try {
      await _lifecycle('untrack', handle);
    } catch (_) {
      /* 窗口可能已关闭。 */
    }
    if (!_exit.isCompleted) _exit.complete(error);
    return error;
  }
}
