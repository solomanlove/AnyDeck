import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../../features/performance/performance_data.dart';

/// 单个 CPU 核心 FFI 结构体映射 (与 Rust CoreUsageFFI 对齐)
final class CoreUsageFFI extends Struct {
  @Uint32()
  external int id;

  @Float()
  external double usage;

  @Float()
  external double freqMHz;
}

/// 整机性能指标瞬时快照 FFI 结构体映射 (与 Rust PerformanceSnapshotFFI 对齐)
final class PerformanceSnapshotFFI extends Struct {
  @Float()
  external double overallCpu;

  @Float()
  external double totalMemMB;

  @Float()
  external double usedMemMB;

  @Float()
  external double memPercent;

  @Float()
  external double fps;

  @Int32()
  external int batteryLevel;

  @Bool()
  external bool isCharging;

  @Uint64()
  external int uptimeSecs;

  @Uint32()
  external int coreCount;

  @Array(32)
  external Array<CoreUsageFFI> cores;

  @Array(256)
  external Array<Uint8> packageName;
}

typedef _PollPerformanceNative =
    Bool Function(Pointer<Uint8>, Pointer<PerformanceSnapshotFFI>);
typedef _PollPerformanceDart =
    bool Function(Pointer<Uint8>, Pointer<PerformanceSnapshotFFI>);

typedef _ClearCacheNative = Void Function(Pointer<Uint8>);
typedef _ClearCacheDart = void Function(Pointer<Uint8>);

/// 针对 Rust Device Bridge 性能监控接口的 FFI 桥接服务。
/// 采用单例静态内存复用机制，消除每次轮询产生的堆内存分配。
class RustPerformanceBridge {
  RustPerformanceBridge._(this.library) {
    _alloc = library
        .lookupFunction<
          Pointer<Uint8> Function(UintPtr),
          Pointer<Uint8> Function(int)
        >('anydeck_alloc');
    _free = library
        .lookupFunction<
          Void Function(Pointer<Uint8>, UintPtr),
          void Function(Pointer<Uint8>, int)
        >('anydeck_free');
    _poll = library
        .lookupFunction<_PollPerformanceNative, _PollPerformanceDart>(
          'anydeck_poll_performance',
        );
    _clearCache = library.lookupFunction<_ClearCacheNative, _ClearCacheDart>(
      'anydeck_clear_performance_cache',
    );

    // 预分配单个静态快照缓冲区，轮询期间循环复用
    _snapshotSize = sizeOf<PerformanceSnapshotFFI>();
    _snapshotBuffer = _alloc(_snapshotSize);
    if (_snapshotBuffer == nullptr) {
      throw StateError('Failed to allocate PerformanceSnapshotFFI buffer');
    }
    _snapshotBuffer.asTypedList(_snapshotSize).fillRange(0, _snapshotSize, 0);
    _snapshotPtr = _snapshotBuffer.cast<PerformanceSnapshotFFI>();
  }

  final DynamicLibrary library;
  static final RustPerformanceBridge instance = RustPerformanceBridge._(
    _open(),
  );

  late final Pointer<Uint8> Function(int) _alloc;
  late final void Function(Pointer<Uint8>, int) _free;
  late final _PollPerformanceDart _poll;
  late final _ClearCacheDart _clearCache;

  late final int _snapshotSize;
  late final Pointer<Uint8> _snapshotBuffer;
  late final Pointer<PerformanceSnapshotFFI> _snapshotPtr;

  static DynamicLibrary _open() {
    final customPath = Platform.environment['ANYDECK_DEVICE_BRIDGE'];
    if (customPath != null && customPath.isNotEmpty) {
      return DynamicLibrary.open(customPath);
    }
    if (!Platform.isMacOS) {
      throw UnsupportedError(
        'RustPerformanceBridge is currently only supported on macOS',
      );
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

  /// 轮询指定设备的性能指标快照；若 Rust 底层执行失败则返回 null。
  PerformanceSnapshot? poll(String serial) {
    if (serial.contains('\u0000')) return null;
    final bytesLen = utf8.encode(serial).length + 1;
    final serialPtr = _stringToBuffer(serial);

    try {
      final success = _poll(serialPtr, _snapshotPtr);
      if (!success) return null;

      final snapshotRef = _snapshotPtr.ref;
      final timestamp = DateTime.now();

      // 1. 格式化运行时间 (uptime)
      final totalSecs = snapshotRef.uptimeSecs;
      final days = totalSecs ~/ 86400;
      final hours = (totalSecs % 86400) ~/ 3600;
      final minutes = (totalSecs % 3600) ~/ 60;
      final secs = totalSecs % 60;
      final uptimeStr =
          '${days > 0 ? '$days天' : ''}'
          '${hours.toString().padLeft(2, '0')}时'
          '${minutes.toString().padLeft(2, '0')}分'
          '${secs.toString().padLeft(2, '0')}秒';

      // 2. 读取前台应用包名
      final pkgBytes = <int>[];
      for (var i = 0; i < 256; i++) {
        final b = snapshotRef.packageName[i];
        if (b == 0) break;
        pkgBytes.add(b);
      }
      final foregroundPkg = utf8.decode(pkgBytes, allowMalformed: true);

      // 3. 读取各核心指标
      final coreCount = snapshotRef.coreCount.clamp(0, 32);
      final coreSnapshots = <CpuCoreSnapshot>[];
      for (var i = 0; i < coreCount; i++) {
        final c = snapshotRef.cores[i];
        coreSnapshots.add(
          CpuCoreSnapshot(
            id: c.id,
            usage: c.usage,
            frequencyMHz: c.freqMHz,
          ),
        );
      }

      return PerformanceSnapshot(
        uptime: uptimeStr,
        batteryLevel: snapshotRef.batteryLevel,
        isCharging: snapshotRef.isCharging,
        totalMemoryMB: snapshotRef.totalMemMB,
        usedMemoryMB: snapshotRef.usedMemMB,
        memoryUsagePercent: snapshotRef.memPercent,
        foregroundAppPackage: foregroundPkg,
        overallCpuUsage: snapshotRef.overallCpu,
        cores: coreSnapshots,
        totalFrames: 0,
        fps: snapshotRef.fps,
        timestamp: timestamp,
      );
    } catch (_) {
      return null;
    } finally {
      _free(serialPtr, bytesLen);
    }
  }

  /// 清除指定设备的性能采样状态缓存
  void clearCache(String serial) {
    if (serial.contains('\u0000')) return;
    final bytesLen = utf8.encode(serial).length + 1;
    final serialPtr = _stringToBuffer(serial);
    try {
      _clearCache(serialPtr);
    } catch (_) {
      // 容错处理
    } finally {
      _free(serialPtr, bytesLen);
    }
  }

  /// 释放静态预分配的原生内存
  void dispose() {
    _free(_snapshotBuffer, _snapshotSize);
  }
}
