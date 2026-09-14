import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Rust C ABI 的薄封装；Flutter 不解析设备协议，不承担进程或音视频处理。
class RustDeviceBridge {
  RustDeviceBridge._(this.library);
  final DynamicLibrary library;
  static final instance = RustDeviceBridge._(_open());

  static DynamicLibrary _open() {
    final customPath = Platform.environment['ANYDECK_DEVICE_BRIDGE'];
    if (customPath != null && customPath.isNotEmpty) {
      return DynamicLibrary.open(customPath);
    }
    if (!Platform.isMacOS) {
      throw UnsupportedError(
        'RustDeviceBridge is currently only supported on macOS',
      );
    }
    // 优先加载 App Bundle Frameworks 中的统一动态库，
    // 确保与 Swift 原生插件 (RustTexturePlugin) 共享同一内存镜像与 static 会话状态。
    final frameworksPath =
        '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks/libanydeck_device_bridge.dylib';
    if (File(frameworksPath).existsSync()) {
      return DynamicLibrary.open(frameworksPath);
    }
    final projectLibsPath =
        '${Directory.current.path}/macos/Libs/libanydeck_device_bridge.dylib';
    if (File(projectLibsPath).existsSync()) {
      return DynamicLibrary.open(projectLibsPath);
    }
    return DynamicLibrary.open(frameworksPath);
  }
  late final _start = library
      .lookupFunction<
        Uint64 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Uint8),
        int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, int)
      >('anydeck_start');
  late final status = library
      .lookupFunction<Uint8 Function(Uint64), int Function(int)>(
        'anydeck_status',
      );
  late final stop = library
      .lookupFunction<Void Function(Uint64), void Function(int)>(
        'anydeck_stop',
      );
  late final release = library
      .lookupFunction<Void Function(Uint64), void Function(int)>(
        'anydeck_release',
      );
  late final refresh = library
      .lookupFunction<Void Function(Uint64), void Function(int)>(
        'anydeck_refresh',
      );
  late final mute = library
      .lookupFunction<Void Function(Uint64, Uint8), void Function(int, int)>(
        'anydeck_mute',
      );
  late final revision = library
      .lookupFunction<Uint64 Function(Uint64), int Function(int)>(
        'anydeck_revision',
      );
  late final videoSize = library
      .lookupFunction<Uint64 Function(Uint64), int Function(int)>(
        'anydeck_video_size',
      );
  late final _startMirror = library
      .lookupFunction<
        Uint64 Function(Pointer<Uint8>, Int32, Uint8),
        int Function(Pointer<Uint8>, int, int)
      >('anydeck_start_mirror');
  late final _sendControl = library
      .lookupFunction<
        Bool Function(Uint64, Pointer<Uint8>, UintPtr),
        bool Function(int, Pointer<Uint8>, int)
      >('anydeck_send_control');
  late final _clipboard = library
      .lookupFunction<
        UintPtr Function(Uint64, Pointer<Uint8>, UintPtr),
        int Function(int, Pointer<Uint8>, int)
      >('anydeck_clipboard');
  late final _alloc = library
      .lookupFunction<
        Pointer<Uint8> Function(UintPtr),
        Pointer<Uint8> Function(int)
      >('anydeck_alloc');
  late final _free = library
      .lookupFunction<
        Void Function(Pointer<Uint8>, UintPtr),
        void Function(Pointer<Uint8>, int)
      >('anydeck_free');

  int start(String adb, String serial, String jar, int kind) {
    final buffers = <(Pointer<Uint8>, int)>[];
    try {
      for (final string in [adb, serial, jar]) {
        if (string.contains('\u0000')) {
          throw ArgumentError('NUL in native argument');
        }
        final bytes = utf8.encode(string);
        final pointer = _alloc(bytes.length + 1);
        if (pointer == nullptr) throw StateError('Native allocation failed');
        buffers.add((pointer, bytes.length + 1));
        final list = pointer.asTypedList(bytes.length + 1);
        list.setAll(0, bytes);
        list[bytes.length] = 0;
      }
      return _start(buffers[0].$1, buffers[1].$1, buffers[2].$1, kind);
    } finally {
      for (final buffer in buffers) {
        _free(buffer.$1, buffer.$2);
      }
    }
  }

  String clipboard(int handle) {
    const capacity = 256 * 1024;
    final pointer = _alloc(capacity);
    if (pointer == nullptr) throw StateError('Native allocation failed');
    try {
      final size = _clipboard(handle, pointer, capacity);
      if (size > capacity) throw StateError('Clipboard exceeds limit');
      return utf8.decode(pointer.asTypedList(size));
    } finally {
      _free(pointer, capacity);
    }
  }

  int startMirror(String host, int port, bool audioEnabled) {
    if (host.contains('\u0000')) {
      throw ArgumentError('NUL in native argument');
    }
    final bytes = utf8.encode(host);
    final pointer = _alloc(bytes.length + 1);
    if (pointer == nullptr) throw StateError('Native allocation failed');
    try {
      final list = pointer.asTypedList(bytes.length + 1);
      list.setAll(0, bytes);
      list[bytes.length] = 0;
      return _startMirror(pointer, port, audioEnabled ? 1 : 0);
    } finally {
      _free(pointer, bytes.length + 1);
    }
  }

  bool sendControl(int handle, Uint8List controlMessage) {
    if (controlMessage.isEmpty) return false;
    final pointer = _alloc(controlMessage.length);
    if (pointer == nullptr) throw StateError('Native allocation failed');
    try {
      pointer.asTypedList(controlMessage.length).setAll(0, controlMessage);
      return _sendControl(handle, pointer, controlMessage.length);
    } finally {
      _free(pointer, controlMessage.length);
    }
  }
}
