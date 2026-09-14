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

typedef _ListIosDevicesNative = Pointer<Uint8> Function();
typedef _ListIosDevicesDart = Pointer<Uint8> Function();

typedef _BleMouseStartNative = Uint8 Function();
typedef _BleMouseStartDart = int Function();

typedef _BleMouseStopNative = Uint8 Function();
typedef _BleMouseStopDart = int Function();

typedef _BleMouseSendNative = Uint8 Function(Uint8, Int8, Int8, Int8);
typedef _BleMouseSendDart = int Function(int, int, int, int);

typedef _BleMouseStatusNative = Uint8 Function();
typedef _BleMouseStatusDart = int Function();

typedef _WdaRequestNative =
    Pointer<Uint8> Function(
      Uint16,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
    );
typedef _WdaRequestDart =
    Pointer<Uint8> Function(
      int,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
    );

typedef _CronAddJobNative =
    Uint8 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);
typedef _CronAddJobDart =
    int Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>);

typedef _CronRemoveJobNative = Uint8 Function(Pointer<Uint8>);
typedef _CronRemoveJobDart = int Function(Pointer<Uint8>);

typedef _CronListJobsNative = Pointer<Uint8> Function();
typedef _CronListJobsDart = Pointer<Uint8> Function();

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
        try {
          _listIosDevices = _library
              .lookupFunction<_ListIosDevicesNative, _ListIosDevicesDart>(
                'anydeck_ios_list_devices',
              );
        } catch (_) {
          _listIosDevices = null;
        }
        try {
          _bleMouseStart = _library
              .lookupFunction<_BleMouseStartNative, _BleMouseStartDart>(
                'anydeck_ble_mouse_start',
              );
          _bleMouseStop = _library
              .lookupFunction<_BleMouseStopNative, _BleMouseStopDart>(
                'anydeck_ble_mouse_stop',
              );
          _bleMouseSend = _library
              .lookupFunction<_BleMouseSendNative, _BleMouseSendDart>(
                'anydeck_ble_mouse_send',
              );
          _bleMouseStatus = _library
              .lookupFunction<_BleMouseStatusNative, _BleMouseStatusDart>(
                'anydeck_ble_mouse_status',
              );
        } catch (_) {
          _bleMouseStart = null;
          _bleMouseStop = null;
          _bleMouseSend = null;
          _bleMouseStatus = null;
        }
        try {
          _wdaRequest = _library
              .lookupFunction<_WdaRequestNative, _WdaRequestDart>(
                'anydeck_wda_request',
              );
        } catch (_) {
          _wdaRequest = null;
        }
        try {
          _cronAddJob = _library
              .lookupFunction<_CronAddJobNative, _CronAddJobDart>(
                'anydeck_cron_add_job',
              );
          _cronRemoveJob = _library
              .lookupFunction<_CronRemoveJobNative, _CronRemoveJobDart>(
                'anydeck_cron_remove_job',
              );
          _cronListJobs = _library
              .lookupFunction<_CronListJobsNative, _CronListJobsDart>(
                'anydeck_cron_list_jobs',
              );
        } catch (_) {
          _cronAddJob = null;
          _cronRemoveJob = null;
          _cronListJobs = null;
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
  _ListIosDevicesDart? _listIosDevices;
  _BleMouseStartDart? _bleMouseStart;
  _BleMouseStopDart? _bleMouseStop;
  _BleMouseSendDart? _bleMouseSend;
  _BleMouseStatusDart? _bleMouseStatus;
  _WdaRequestDart? _wdaRequest;
  _CronAddJobDart? _cronAddJob;
  _CronRemoveJobDart? _cronRemoveJob;
  _CronListJobsDart? _cronListJobs;
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

  /// 查询已连接的 iOS 设备列表
  Future<List<Map<String, dynamic>>> listIosDevices() async {
    if (!_isInitialized || _listIosDevices == null) {
      return [];
    }

    Pointer<Uint8> resultPtr = nullptr;
    try {
      resultPtr = _listIosDevices!();
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

  /// 开启蓝牙 BLE HID 鼠标广播
  bool bleMouseStart() {
    if (!_isInitialized || _bleMouseStart == null) return false;
    return _bleMouseStart!() != 0;
  }

  /// 停止蓝牙 BLE HID 鼠标广播
  bool bleMouseStop() {
    if (!_isInitialized || _bleMouseStop == null) return false;
    return _bleMouseStop!() != 0;
  }

  /// 发送蓝牙鼠标相对移动与按键 (buttons: 1:左键, 2:右键, 4:中键)
  bool bleMouseSend({
    required int buttons,
    required int dx,
    required int dy,
    int wheel = 0,
  }) {
    if (!_isInitialized || _bleMouseSend == null) return false;
    return _bleMouseSend!(
          buttons.clamp(0, 255),
          dx.clamp(-127, 127),
          dy.clamp(-127, 127),
          wheel.clamp(-127, 127),
        ) !=
        0;
  }

  /// 查询当前 BLE 虚拟鼠标状态 (0: 停止, 1: 广播等待连接, 2: 已连接活跃)
  int bleMouseStatus() {
    if (!_isInitialized || _bleMouseStatus == null) return 0;
    return _bleMouseStatus!();
  }

  /// 向 WebDriverAgent 发送轻量级 HTTP 自动化请求
  Future<Map<String, dynamic>> wdaRequest({
    required int port,
    required String endpoint,
    required String method,
    String? bodyJson,
  }) async {
    if (!_isInitialized || _wdaRequest == null) {
      return {'success': false, 'payload': 'WDA FFI not available'};
    }

    final epLen = utf8.encode(endpoint).length + 1;
    final mLen = utf8.encode(method).length + 1;
    final bLen = bodyJson != null ? utf8.encode(bodyJson).length + 1 : 0;

    final epPtr = _stringToBuffer(endpoint);
    final mPtr = _stringToBuffer(method);
    final bPtr = bodyJson != null ? _stringToBuffer(bodyJson) : nullptr;

    Pointer<Uint8> resultPtr = nullptr;
    try {
      resultPtr = _wdaRequest!(port, epPtr, mPtr, bPtr);
      if (resultPtr == nullptr) {
        return {'success': false, 'payload': 'Null response from WDA'};
      }

      final jsonStr = _cStringToString(resultPtr);
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'success': false, 'payload': jsonStr};
    } catch (e) {
      return {'success': false, 'payload': e.toString()};
    } finally {
      if (resultPtr != nullptr) {
        _freeString(resultPtr);
      }
      _free(epPtr, epLen);
      _free(mPtr, mLen);
      if (bPtr != nullptr) {
        _free(bPtr, bLen);
      }
    }
  }

  /// 注册或更新 Cron 定时调度任务
  bool cronAddJob({
    required String id,
    required String name,
    required String expression,
  }) {
    if (!_isInitialized || _cronAddJob == null) return false;

    final idLen = utf8.encode(id).length + 1;
    final nameLen = utf8.encode(name).length + 1;
    final exprLen = utf8.encode(expression).length + 1;

    final idPtr = _stringToBuffer(id);
    final namePtr = _stringToBuffer(name);
    final exprPtr = _stringToBuffer(expression);

    try {
      return _cronAddJob!(idPtr, namePtr, exprPtr) != 0;
    } finally {
      _free(idPtr, idLen);
      _free(namePtr, nameLen);
      _free(exprPtr, exprLen);
    }
  }

  /// 移除 Cron 定时调度任务
  bool cronRemoveJob(String id) {
    if (!_isInitialized || _cronRemoveJob == null) return false;

    final idLen = utf8.encode(id).length + 1;
    final idPtr = _stringToBuffer(id);
    try {
      return _cronRemoveJob!(idPtr) != 0;
    } finally {
      _free(idPtr, idLen);
    }
  }

  /// 查询 Cron 定时调度任务清单
  List<Map<String, dynamic>> cronListJobs() {
    if (!_isInitialized || _cronListJobs == null) return [];

    Pointer<Uint8> resultPtr = nullptr;
    try {
      resultPtr = _cronListJobs!();
      if (resultPtr == nullptr) return [];

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
}
