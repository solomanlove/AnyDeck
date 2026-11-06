import 'dart:async';
import 'dart:isolate';

import '../../features/performance/performance_data.dart';
import 'rust_performance_bridge.dart';

/// 每个可见性能页持有一个常驻 worker；FFI 指针和缓冲区只在 worker 中使用。
class PerformanceSampler {
  PerformanceSampler({
    this.libraryPath,
    this.timeout = const Duration(seconds: 4),
  });

  final String? libraryPath;
  final Duration timeout;
  SendPort? _commands;
  Future<void>? _starting;
  Completer<PerformanceSnapshot?>? _pending;
  String? _serial;
  bool _closed = false;
  final _stopped = Completer<void>();

  /// 在原生缓冲区释放、worker 退出后完成，供切页恢复时避免新旧 worker 重叠。
  Future<void> get stopped => _stopped.future;

  /// 慢查询期间复用同一 Future，避免向 worker 排入无限采样请求。
  Future<PerformanceSnapshot?> poll(String serial) {
    if (_closed || serial.isEmpty || serial.contains('\u0000')) {
      return Future.value();
    }
    if (_pending != null) {
      return _serial == serial ? _pending!.future : Future.value();
    }
    final pending = _pending = Completer<PerformanceSnapshot?>();
    _serial = serial;
    unawaited(_poll(serial, pending));
    return pending.future;
  }

  Future<void> _poll(
    String serial,
    Completer<PerformanceSnapshot?> pending,
  ) async {
    try {
      await (_starting ??= _start()).timeout(timeout);
      if (_closed) return;
      _commands!.send(serial);
      await pending.future.timeout(timeout);
    } catch (_) {
      // worker 崩溃或超时后释放端口；调用方可以回退到已有 CLI。
      dispose();
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  Future<void> _start() async {
    final ready = Completer<void>();
    final responses = ReceivePort();
    responses.listen((message) {
      if (message is SendPort) {
        _commands = message;
        if (!ready.isCompleted) ready.complete();
      } else if (message is PerformanceSnapshot || message == false) {
        final pending = _pending;
        if (pending != null && !pending.isCompleted) {
          _pending = null;
          pending.complete(message is PerformanceSnapshot ? message : null);
        }
      } else {
        if (!ready.isCompleted) ready.complete();
        dispose();
        responses.close();
        if (!_stopped.isCompleted) _stopped.complete();
      }
    });
    try {
      await Isolate.spawn(
        _performanceWorker,
        (responses.sendPort, libraryPath),
        onError: responses.sendPort,
        onExit: responses.sendPort,
      );
    } catch (_) {
      responses.close();
      if (!_stopped.isCompleted) _stopped.complete();
      rethrow;
    }
    await ready.future;
    if (_closed) _commands?.send(null);
  }

  /// 切页/切设备立即失效在途结果，worker 在原生调用返回后释放私有内存。
  void dispose() {
    if (_closed) return;
    _closed = true;
    if (_starting == null && !_stopped.isCompleted) _stopped.complete();
    _commands?.send(null);
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete();
  }
}

/// 保持同步 FFI 的资源所有权，正常关闭时对称释放缓冲区及设备增量缓存。
void _performanceWorker((SendPort, String?) configuration) {
  final (responses, libraryPath) = configuration;
  final bridge = RustPerformanceBridge.open(libraryPath: libraryPath);
  final commands = ReceivePort();
  String? lastSerial;
  responses.send(commands.sendPort);
  commands.listen((message) {
    if (message == null) {
      if (lastSerial != null) bridge.clearCache(lastSerial!);
      bridge.dispose();
      commands.close();
      return;
    }
    final serial = message as String;
    if (lastSerial != null && lastSerial != serial) {
      bridge.clearCache(lastSerial!);
    }
    lastSerial = serial;
    responses.send(bridge.poll(serial) ?? false);
  });
}
