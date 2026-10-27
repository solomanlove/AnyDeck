import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../scrcpy/rust_device_bridge.dart';

typedef _ReadNative = UintPtr Function(Uint64, Pointer<Uint8>, UintPtr);
typedef _ReadDart = int Function(int, Pointer<Uint8>, int);
typedef _UpdateNative =
    Void Function(Uint64, Uint64, Double, Double, Double, Uint8);
typedef _UpdateDart = void Function(int, int, double, double, double, int);

/// HTTP 视频信令单独通过有界快照传递，不占用镜像纹理或传递视频帧。
class AirPlayVideoBridge {
  AirPlayVideoBridge() {
    final library = RustDeviceBridge.instance.library;
    _read = library.lookupFunction<_ReadNative, _ReadDart>(
      'anydeck_airplay_copy_media_state',
    );
    _update = library.lookupFunction<_UpdateNative, _UpdateDart>(
      'anydeck_airplay_update_media_state',
    );
  }

  late final _ReadDart _read;
  late final _UpdateDart _update;

  Map<String, dynamic>? read(int handle) {
    const capacity = 65536;
    final buffer = calloc<Uint8>(capacity);
    try {
      final length = _read(handle, buffer, capacity);
      if (length <= 0 || length > capacity) return null;
      return jsonDecode(utf8.decode(buffer.asTypedList(length)))
          as Map<String, dynamic>;
    } finally {
      calloc.free(buffer);
    }
  }

  void report(int handle, int generation, Map<dynamic, dynamic> state) {
    _update(
      handle,
      generation,
      (state['duration'] as num? ?? 0).toDouble(),
      (state['position'] as num? ?? 0).toDouble(),
      (state['rate'] as num? ?? 0).toDouble(),
      (state['state'] as num? ?? 0).toInt(),
    );
  }
}
