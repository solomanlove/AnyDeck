import 'dart:convert';
import 'dart:ffi';

import 'rust_device_bridge.dart';

/// 可替换的内存态 API，音视频包不会逐帧穿过 Dart FFI。
abstract class RecordingNativeApi {
  int start(String adb, String serial, String jar, String path);
  int status(int handle);
  String error(int handle);
  void stop(int handle);
  void release(int handle);
}

/// Rust 录制 C ABI 的薄封装，复用 App 内动态库及对称内存分配。
class RustRecordingApi implements RecordingNativeApi {
  RustRecordingApi() : _bridge = RustDeviceBridge.instance;
  final RustDeviceBridge _bridge;
  late final _start = _bridge.library
      .lookupFunction<
        Uint64 Function(
          Pointer<Uint8>,
          Pointer<Uint8>,
          Pointer<Uint8>,
          Pointer<Uint8>,
        ),
        int Function(
          Pointer<Uint8>,
          Pointer<Uint8>,
          Pointer<Uint8>,
          Pointer<Uint8>,
        )
      >('anydeck_start_recording');
  late final _error = _bridge.library
      .lookupFunction<
        UintPtr Function(Uint64, Pointer<Uint8>, UintPtr),
        int Function(int, Pointer<Uint8>, int)
      >('anydeck_recording_error');
  late final _alloc = _bridge.library
      .lookupFunction<
        Pointer<Uint8> Function(UintPtr),
        Pointer<Uint8> Function(int)
      >('anydeck_alloc');
  late final _free = _bridge.library
      .lookupFunction<
        Void Function(Pointer<Uint8>, UintPtr),
        void Function(Pointer<Uint8>, int)
      >('anydeck_free');

  @override
  int start(String adb, String serial, String jar, String path) {
    final buffers = <(Pointer<Uint8>, int)>[];
    try {
      for (final value in [adb, serial, jar, path]) {
        if (value.contains('\u0000')) {
          throw ArgumentError('NUL in recording argument');
        }
        final bytes = utf8.encode(value);
        final pointer = _alloc(bytes.length + 1);
        if (pointer == nullptr) throw StateError('Native allocation failed');
        buffers.add((pointer, bytes.length + 1));
        pointer.asTypedList(bytes.length + 1)
          ..setAll(0, bytes)
          ..[bytes.length] = 0;
      }
      return _start(buffers[0].$1, buffers[1].$1, buffers[2].$1, buffers[3].$1);
    } finally {
      for (final (pointer, size) in buffers) {
        _free(pointer, size);
      }
    }
  }

  @override
  String error(int handle) {
    final size = _error(handle, nullptr, 0);
    if (size == 0) return '';
    if (size > 4096) return 'Invalid native recording error';
    final pointer = _alloc(4096);
    if (pointer == nullptr) return 'Native allocation failed';
    try {
      final length = _error(handle, pointer, 4096);
      if (length > 4096) return 'Invalid native recording error';
      return utf8.decode(pointer.asTypedList(length));
    } finally {
      _free(pointer, 4096);
    }
  }

  @override
  int status(int handle) => _bridge.status(handle);
  @override
  void stop(int handle) => _bridge.stop(handle);
  @override
  void release(int handle) => _bridge.release(handle);
}
