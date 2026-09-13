import 'dart:async';

import 'package:flutter/services.dart';

import 'rust_device_bridge.dart';

/// Rust 句柄生命周期适配；轮询的只是内存状态，设备 I/O 完全由 Rust 执行。
class RustDeviceSession {
  RustDeviceSession({
    required this.adb,
    required this.deviceId,
    required this.resolveJar,
    required this.kind,
  });
  final String adb;
  final String deviceId;
  final Future<String> Function() resolveJar;
  final int kind;
  static const _lifecycle = MethodChannel('anydeck/rust_texture');
  RustDeviceBridge? _bridge;
  int? _handle;
  int get handle => _handle!;
  bool _cancelled = false;
  Future<void>? _starting;
  Future<void>? _stopping;
  Timer? _poll;
  int _revision = 0;
  final _clipboard = StreamController<String>.broadcast();
  final _exit = Completer<void>();
  Stream<String> get clipboard => _clipboard.stream;
  Future<void> get exited => _exit.future;

  Future<void> start() => _starting = _start();
  Future<void> _start() async {
    final jar = await resolveJar();
    if (_cancelled) throw StateError('Session cancelled');
    final bridge = _bridge = RustDeviceBridge.instance;
    final id = _handle = bridge.start(adb, deviceId, jar, kind);
    if (id == 0) throw StateError('Rust session creation failed');
    // 窗口/Engine 关闭时由薄平台桥接回收，避免 Isolate 销毁后留下 Rust 线程。
    await _lifecycle
        .invokeMethod<void>('track', {'handle': id})
        .timeout(const Duration(seconds: 3));
    final deadline = DateTime.now().add(const Duration(seconds: 75));
    while (!_cancelled) {
      final status = bridge.status(id);
      if (status == 1) break;
      if (status >= 2 || DateTime.now().isAfter(deadline)) {
        throw StateError('Rust session start failed');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_cancelled) throw StateError('Session cancelled');
    _poll = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_cancelled) return;
      if (bridge.status(id) >= 2) {
        _poll?.cancel();
        if (!_exit.isCompleted) _exit.complete();
        return;
      }
      if (kind == 2) {
        final revision = bridge.revision(id);
        if (revision != _revision) {
          _revision = revision;
          _clipboard.add(bridge.clipboard(id));
        }
      }
    });
  }

  Map<String, int> videoSize() {
    final id = _handle;
    final size = id == null ? 0 : _bridge!.videoSize(id);
    return {'width': size >> 32, 'height': size & 0xffffffff};
  }

  void mute(bool muted) {
    if (!_cancelled && _handle != null) _bridge!.mute(handle, muted ? 1 : 0);
  }

  void refresh() {
    if (!_cancelled && _handle != null) _bridge!.refresh(handle);
  }

  void cancel() {
    _cancelled = true;
    _poll?.cancel();
    if (_handle != null) _bridge!.stop(handle);
  }

  Future<void> stop() => _stopping ??= _stop();
  Future<void> _stop() async {
    cancel();
    try {
      await _starting;
    } catch (_) {}
    final id = _handle;
    if (id != null) {
      final bridge = _bridge!;
      // Rust Drop 在异常路径可能补查映射，清理命令均有 15s 上限，UI 保持“正在停止”。
      final deadline = DateTime.now().add(const Duration(seconds: 65));
      while (bridge.status(id) < 2 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final complete = bridge.status(id) >= 2;
      bridge.release(id);
      _handle = null;
      try {
        await _lifecycle
            .invokeMethod<void>('untrack', {'handle': id})
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        /* 窗口已销毁时，Rust 句柄仍已释放。 */
      }
      await _clipboard.close();
      if (!complete) throw StateError('Rust cleanup timed out');
    } else {
      await _clipboard.close();
    }
  }
}
