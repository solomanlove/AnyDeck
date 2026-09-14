import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'device_driver.dart';

typedef _BatchExecuteNative =
    Pointer<Uint8> Function(Uint8, Pointer<Uint8>, Pointer<Uint8>, Uint32);
typedef _BatchExecuteDart =
    Pointer<Uint8> Function(int, Pointer<Uint8>, Pointer<Uint8>, int);

typedef _DalExecuteNative =
    Pointer<Uint8> Function(Uint8, Pointer<Uint8>, Pointer<Uint8>);
typedef _DalExecuteDart =
    Pointer<Uint8> Function(int, Pointer<Uint8>, Pointer<Uint8>);

typedef _ListHarmonyDevicesNative = Pointer<Uint8> Function();
typedef _ListHarmonyDevicesDart = Pointer<Uint8> Function();

typedef _FreeStringNative = Void Function(Pointer<Uint8>);
typedef _FreeStringDart = void Function(Pointer<Uint8>);

/// 统一设备抽象层 (DAL) 与批量并发引擎的 Rust FFI 桥接单例
class RustDalBridge {
  RustDalBridge._(DynamicLibrary? lib) : _library = lib {
    if (_library != null) {
      try {
        _alloc = _library
            .lookupFunction<
              Pointer<Uint8> Function(UintPtr),
              Pointer<Uint8> Function(int)
            >('anydeck_alloc');
        _free = _library
            .lookupFunction<
              Void Function(Pointer<Uint8>, UintPtr),
              void Function(Pointer<Uint8>, int)
            >('anydeck_free');
        _batchExecute = _library
            .lookupFunction<_BatchExecuteNative, _BatchExecuteDart>(
              'anydeck_batch_execute_shell',
            );
        _dalExecute = _library
            .lookupFunction<_DalExecuteNative, _DalExecuteDart>(
              'anydeck_dal_execute_shell',
            );
        try {
          _listHarmonyDevices = _library
              .lookupFunction<_ListHarmonyDevicesNative, _ListHarmonyDevicesDart>(
                'anydeck_harmony_list_devices',
              );
        } catch (_) {
          _listHarmonyDevices = null;
        }
        _freeString = _library
            .lookupFunction<_FreeStringNative, _FreeStringDart>(
              'anydeck_free_string',
            );
        _isInitialized = true;
      } catch (_) {
        _isInitialized = false;
      }
    } else {
      _isInitialized = false;
    }
  }

  final DynamicLibrary? _library;
  bool _isInitialized = false;

  late final Pointer<Uint8> Function(int) _alloc;
  late final void Function(Pointer<Uint8>, int) _free;
  late final _BatchExecuteDart _batchExecute;
  late final _DalExecuteDart _dalExecute;
  _ListHarmonyDevicesDart? _listHarmonyDevices;
  late final _FreeStringDart _freeString;

  static final RustDalBridge instance = RustDalBridge._(_tryOpen());

  /// 底层 Rust 桥接与动态库是否就绪可用
  bool get isAvailable => _isInitialized;

  static DynamicLibrary? _tryOpen() {
    try {
      final customPath = Platform.environment['ANYDECK_DEVICE_BRIDGE'];
      if (customPath != null && customPath.isNotEmpty) {
        return DynamicLibrary.open(customPath);
      }
      if (!Platform.isMacOS) {
        return null;
      }
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
    } catch (_) {
      return null;
    }
  }

  Pointer<Uint8> _stringToBuffer(String string) {
    final bytes = utf8.encode(string);
    final pointer = _alloc(bytes.length + 1);
    if (pointer == nullptr) throw StateError('Native allocation failed');
    final list = pointer.asTypedList(bytes.length + 1);
    list.setAll(0, bytes);
    list[bytes.length] = 0;
    return pointer;
  }

  String _cStringToString(Pointer<Uint8> ptr) {
    final bytes = <int>[];
    var offset = 0;
    while (true) {
      final b = (ptr + offset).value;
      if (b == 0) break;
      bytes.add(b);
      offset++;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 批量并发执行控制台 Shell 指令 (受 Tokio 与信号量硬限流保护)
  Future<List<BatchDeviceResult>> executeBatchShell(
    List<String> serials,
    String command, {
    int maxConcurrency = 4,
    DevicePlatform platform = DevicePlatform.android,
  }) async {
    if (!_isInitialized || serials.isEmpty) {
      return [];
    }

    final serialsJson = jsonEncode(serials);
    final serialsBytesLen = utf8.encode(serialsJson).length + 1;
    final cmdBytesLen = utf8.encode(command).length + 1;

    final serialsPtr = _stringToBuffer(serialsJson);
    final cmdPtr = _stringToBuffer(command);

    Pointer<Uint8> resultPtr = nullptr;
    try {
      resultPtr = _batchExecute(
        platform.value,
        serialsPtr,
        cmdPtr,
        maxConcurrency,
      );
      if (resultPtr == nullptr) {
        return [];
      }

      final jsonString = _cStringToString(resultPtr);
      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(BatchDeviceResult.fromJson)
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    } finally {
      if (resultPtr != nullptr) {
        _freeString(resultPtr);
      }
      _free(serialsPtr, serialsBytesLen);
      _free(cmdPtr, cmdBytesLen);
    }
  }

  /// 获取已连接的鸿蒙设备列表 (通过 Rust HDC 驱动原生解析)
  Future<List<Map<String, dynamic>>> listHarmonyDevices() async {
    if (!_isInitialized || _listHarmonyDevices == null) {
      return [];
    }

    Pointer<Uint8> resultPtr = nullptr;
    try {
      resultPtr = _listHarmonyDevices!();
      if (resultPtr == nullptr) {
        return [];
      }

      final jsonString = _cStringToString(resultPtr);
      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
      return [];
    } catch (_) {
      return [];
    } finally {
      if (resultPtr != nullptr) {
        _freeString(resultPtr);
      }
    }
  }

  /// 统一设备抽象层单设备执行 Shell 指令
  Future<String> executeShell(
    String serial,
    String command, {
    DevicePlatform platform = DevicePlatform.android,
  }) async {
    if (!_isInitialized) {
      throw StateError('RustDalBridge is not initialized');
    }

    final serialBytesLen = utf8.encode(serial).length + 1;
    final cmdBytesLen = utf8.encode(command).length + 1;

    final serialPtr = _stringToBuffer(serial);
    final cmdPtr = _stringToBuffer(command);

    Pointer<Uint8> resultPtr = nullptr;
    try {
      resultPtr = _dalExecute(platform.value, serialPtr, cmdPtr);
      if (resultPtr == nullptr) {
        throw StateError('Null response from DAL execute shell');
      }

      final jsonString = _cStringToString(resultPtr);
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      final success = map['success'] as bool? ?? false;
      final payload = map['payload'] as String? ?? '';

      if (success) {
        return payload;
      } else {
        throw Exception(payload);
      }
    } finally {
      if (resultPtr != nullptr) {
        _freeString(resultPtr);
      }
      _free(serialPtr, serialBytesLen);
      _free(cmdPtr, cmdBytesLen);
    }
  }
}
