import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../share_socket_reader.dart';

/// 在上一块等待远端 ACK 时预取至多 [capacity] 字节，合并已到达的小块。
/// 只有内部填充任务读取 [ShareSocketReader]；调用方负责关闭底层 Reader。
class AdbStreamReadBuffer {
  AdbStreamReadBuffer(this._reader, this.capacity) {
    if (capacity <= 0) throw ArgumentError.value(capacity, 'capacity');
    unawaited(_fill());
  }

  final ShareSocketReader _reader;
  final int capacity;
  Uint8List? _buffer;
  int _bytes = 0;
  bool _closed = false, _ended = false;
  Object? _error;
  StackTrace? _errorStack;
  Completer<void>? _available, _space;

  Future<void> _fill() async {
    try {
      while (!_closed) {
        while (!_closed && _bytes == capacity) {
          await (_space ??= Completer<void>()).future;
        }
        if (_closed) return;
        final data = await _reader.readChunk(capacity - _bytes);
        if (_closed) return;
        if (data == null) {
          _ended = true;
          _notifyData();
          return;
        }
        _append(data);
        _notifyData();
      }
    } catch (error, stack) {
      if (!_closed) {
        _error = error;
        _errorStack = stack;
        _ended = true;
        _notifyData();
      }
    }
  }

  void _append(Uint8List data) {
    final required = _bytes + data.length;
    var buffer = _buffer;
    if (buffer == null || buffer.length < required) {
      // 小 Shell 结果从 4 KiB 起步；大流只扩容单块数组，不积累小 chunk 对象。
      var size =
          buffer?.length ?? math.min(capacity, math.max(4096, data.length));
      while (size < required) {
        size = math.min(capacity, size * 2);
      }
      final grown = Uint8List(size);
      if (buffer != null) grown.setRange(0, _bytes, buffer);
      _buffer = buffer = grown;
    }
    buffer.setRange(_bytes, required, data);
    _bytes = required;
  }

  /// 立即取走当前已到达的完整前缀；不等待窗口凑满，不引入聚合 Timer。
  /// EOF 或读取错误都先排空前缀；错误随后交由 Stream 的 device_read 路径诊断。
  Future<Uint8List?> take() async {
    while (!_closed && _bytes == 0 && !_ended) {
      await (_available ??= Completer<void>()).future;
    }
    if (_closed) return null;
    if (_bytes > 0) {
      final output = Uint8List.fromList(
        Uint8List.sublistView(_buffer!, 0, _bytes),
      );
      _bytes = 0;
      _notifySpace();
      return output;
    }
    if (_error case final error?) {
      Error.throwWithStackTrace(error, _errorStack!);
    }
    return null;
  }

  void _notifyData() {
    final available = _available;
    _available = null;
    available?.complete();
  }

  void _notifySpace() {
    final space = _space;
    _space = null;
    space?.complete();
  }

  /// 唤醒所有等待并释放缓存；底层 Socket/Reader 仍由 AdbBridgeStream 回收。
  void close() {
    if (_closed) return;
    _closed = true;
    _buffer = null;
    _bytes = 0;
    _notifyData();
    _notifySpace();
  }
}
