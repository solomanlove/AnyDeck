import 'dart:async';

import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import 'foldable_screen_models.dart';
import 'foldable_screen_parser.dart';
import 'foldable_screen_session.dart';

export 'foldable_screen_session.dart' show FoldableScreenError;

/// 探测运行时布局并确认切屏结果；逻辑主屏继续由 scrcpy 的 display 0 采集。
class FoldableScreenService {
  FoldableScreenService(
    this.adb,
    this.deviceId, {
    FoldableSessionFactory? sessionFactory,
    this.verificationTimeout = const Duration(seconds: 8),
    this.settleInterval = const Duration(milliseconds: 250),
  }) : _sessionFactory =
           sessionFactory ??
           (() => AdbFoldableScreenSession.start(adb, deviceId));

  final AdbService adb;
  final String deviceId;
  final FoldableSessionFactory _sessionFactory;
  final Duration verificationTimeout;
  final Duration settleInterval;
  FoldableScreenSession? _session;
  String? _states;
  String? _displayDump;
  FoldableScreenSnapshot? _snapshot;
  int _generation = 0;
  bool _disposed = false;
  bool _unsupported = false;
  Future<void>? _releasing;

  bool get ownsOverride => _session?.ownsOverride ?? false;

  Future<AdbResult> _read(List<String> args, {Duration? timeout}) =>
      adb.shellArgs(
        deviceId,
        args,
        timeout: timeout ?? const Duration(seconds: 4),
      );

  /// 首次探测完整能力；缺失服务、权限或双向布局时不提供按钮。
  Future<FoldableScreenSnapshot?> probe() async {
    if (_unsupported) return null;
    final generation = _generation;
    final results = await Future.wait([
      _read(['cmd', 'device_state', 'print-states']),
      _read(['cmd', 'device_state', 'state']),
      _read(['dumpsys', 'display']),
      _read(['dumpsys', 'package', 'com.android.shell']),
    ]);
    _checkCurrent(generation);
    if (results.any((result) => !result.isSuccess)) {
      if (results.any((result) => result.exitCode == 124)) {
        throw FoldableScreenError.timeout;
      }
      if (results.any((result) => result.isDeviceDisconnected)) {
        throw FoldableScreenError.unavailable;
      }
      return null;
    }
    if (!RegExp(
      r'android\.permission\.CONTROL_DEVICE_STATE:\s*granted=true',
    ).hasMatch(results[3].stdout)) {
      return null;
    }
    final snapshot = FoldableScreenParser.parse(
      states: results[0].stdout,
      stateDump: results[1].stdout,
      displayDump: results[2].stdout,
    );
    _states = results[0].stdout;
    _displayDump = results[2].stdout;
    return _snapshot = snapshot;
  }

  /// 稳定期间只读取小型状态输出；状态变化时才重新读取显示布局。
  Future<FoldableScreenSnapshot?> refresh({bool readDisplay = false}) async {
    if (_unsupported) return null;
    if (_states == null || _displayDump == null) return probe();
    final generation = _generation;
    final result = await _read(['cmd', 'device_state', 'state']);
    _checkCurrent(generation);
    _requireSuccess(result);
    var snapshot = FoldableScreenParser.parse(
      states: _states!,
      stateDump: result.stdout,
      displayDump: _displayDump!,
    );
    if (readDisplay ||
        snapshot?.committedStateId != _snapshot?.committedStateId) {
      final display = await _read(['dumpsys', 'display']);
      _checkCurrent(generation);
      _requireSuccess(display);
      _displayDump = display.stdout;
      snapshot = FoldableScreenParser.parse(
        states: _states!,
        stateDump: result.stdout,
        displayDump: display.stdout,
      );
    }
    return _snapshot = snapshot;
  }

  /// 请求后同时确认 committed state、override 和真实主屏，失败时释放请求。
  Future<FoldableScreenSnapshot> select(FoldableScreen screen) async {
    await _releasing;
    final generation = _generation;
    final before = await refresh();
    if (before == null || before.currentScreen == null) {
      throw FoldableScreenError.unavailable;
    }
    if (before.hasOverride && !ownsOverride) {
      throw FoldableScreenError.busyExternal;
    }
    var session = _session;
    if (session == null) {
      try {
        session = await _sessionFactory();
      } catch (error) {
        if (error == FoldableScreenError.unsupported) _unsupported = true;
        rethrow;
      }
      if (_disposed || generation != _generation) {
        await session.close();
        throw FoldableScreenError.unavailable;
      }
      _session = session;
    }
    final target = screen == FoldableScreen.inner
        ? before.capability.innerStateId
        : before.capability.outerStateId;
    try {
      _checkCurrent(generation);
      await session.requestState(target);
      _checkCurrent(generation);
      return await _verify(generation, screen: screen, stateId: target);
    } catch (error) {
      if (error == FoldableScreenError.unsupported) _unsupported = true;
      // 不遗留“UI 显示失败，但设备仍被强制固定”的半完成操作。
      if (generation == _generation) await release();
      rethrow;
    }
  }

  Future<FoldableScreenSnapshot> restoreAutomatic() async {
    final generation = _generation;
    if (!ownsOverride) {
      final snapshot = await refresh();
      if (snapshot == null) throw FoldableScreenError.unavailable;
      if (snapshot.hasOverride) throw FoldableScreenError.busyExternal;
      return snapshot;
    }
    await _session!.reset();
    _checkCurrent(generation);
    return _verify(generation);
  }

  Future<FoldableScreenSnapshot> _verify(
    int generation, {
    FoldableScreen? screen,
    int? stateId,
  }) async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < verificationTimeout) {
      _checkCurrent(generation);
      final snapshot = await refresh(readDisplay: true);
      _checkCurrent(generation);
      if (snapshot != null) {
        if (stateId == null && !snapshot.hasOverride) return snapshot;
        final physicalId = screen == FoldableScreen.inner
            ? snapshot.capability.innerPhysicalId
            : snapshot.capability.outerPhysicalId;
        if (snapshot.committedStateId == stateId &&
            snapshot.overrideStateId == stateId &&
            snapshot.currentScreen == screen &&
            _isActivePrimary(physicalId)) {
          return snapshot;
        }
      }
      await Future<void>.delayed(settleInterval);
    }
    throw FoldableScreenError.timeout;
  }

  bool _isActivePrimary(String physicalId) {
    final dump = _displayDump ?? '';
    final physicalLine =
        RegExp(r'^\s*DisplayDeviceInfo\{[^\r\n]+', multiLine: true)
            .allMatches(dump)
            .map((match) => match.group(0)!)
            .where((line) => line.contains('uniqueId="local:$physicalId"'));
    if (!physicalLine.any((line) => RegExp(r'\bstate ON\b').hasMatch(line))) {
      return false;
    }
    final primary = RegExp(
      r'mDisplayId=0\b(?:(?!mDisplayId=)[\s\S])*?mPrimaryDisplayDevice=[^\r\n]*\(local:(\d+)\)',
    ).firstMatch(dump)?.group(1);
    return primary == physicalId;
  }

  void _requireSuccess(AdbResult result) {
    if (result.isSuccess) return;
    throw result.exitCode == 124
        ? FoldableScreenError.timeout
        : FoldableScreenError.unavailable;
  }

  void _checkCurrent(int generation) {
    if (_disposed || generation != _generation) {
      throw FoldableScreenError.unavailable;
    }
  }

  /// USB/TCP 换线、主动停止或 Widget 销毁时，先使迟到操作失效再关闭 Helper。
  Future<void> release() {
    ++_generation;
    final session = _session;
    _session = null;
    final previous = _releasing;
    final operation = () async {
      await previous;
      await session?.close();
    }();
    _releasing = operation;
    return operation;
  }

  Future<void> dispose() {
    _disposed = true;
    return release();
  }
}
