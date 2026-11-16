import 'dart:async';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/foldable/foldable_screen_models.dart';
import 'package:any_deck/core/foldable/foldable_screen_service.dart';
import 'package:any_deck/core/foldable/foldable_screen_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/foldable_screen_fixtures.dart';

/// 验证服务以系统确认结果为准，并在失败与生命周期竞争时释放自身请求。
void main() {
  test('probe 同时确认布局和 Shell 权限，稳定刷新仅读取短状态', () async {
    final adb = _FoldableAdb();
    final service = _service(adb);
    addTearDown(service.dispose);
    final snapshot = await service.probe();
    expect(snapshot?.currentScreen, FoldableScreen.inner);
    expect(adb.commands, contains('dumpsys package com.android.shell'));
    expect(
      adb.timeouts.every((value) => value <= const Duration(seconds: 4)),
      isTrue,
    );
    adb.commands.clear();
    await service.refresh();
    expect(adb.commands, ['cmd device_state state']);
    adb.committed = 0;
    await service.refresh();
    expect(adb.commands.last, 'dumpsys display');
  });

  test('无权限或无双向布局时不开放能力且不启动 Helper', () async {
    for (final adb in [
      _FoldableAdb()..permission = false,
      _FoldableAdb()..states = "DeviceState{identifier=3, name='DEFAULT'}",
    ]) {
      var starts = 0;
      final service = _service(
        adb,
        factory: () async {
          starts++;
          return _FoldableSession(adb);
        },
      );
      addTearDown(service.dispose);
      expect(await service.probe(), isNull);
      expect(starts, 0);
    }
  });

  test('探测时设备断开与命令超时保留可识别失败分类', () async {
    for (final failure in [
      const AdbResult(exitCode: 124, stdout: '', stderr: 'timeout'),
      const AdbResult(
        exitCode: 1,
        stdout: '',
        stderr: "adb: device 'test' not found",
      ),
    ]) {
      final adb = _FoldableAdb()..failures['cmd device_state state'] = failure;
      final service = _service(adb);
      addTearDown(service.dispose);
      await expectLater(
        service.probe(),
        throwsA(
          failure.exitCode == 124
              ? FoldableScreenError.timeout
              : FoldableScreenError.unavailable,
        ),
      );
    }
  });

  test('同一 Helper 完成内外屏往返并确认真实主屏', () async {
    final adb = _FoldableAdb();
    final session = _FoldableSession(adb);
    var starts = 0;
    final service = _service(
      adb,
      factory: () async {
        starts++;
        return session;
      },
    );
    addTearDown(service.dispose);
    final outer = await service.select(FoldableScreen.outer);
    expect(outer.currentScreen, FoldableScreen.outer);
    expect(outer.overrideStateId, 0);
    expect(service.ownsOverride, isTrue);
    final inner = await service.select(FoldableScreen.inner);
    expect(inner.currentScreen, FoldableScreen.inner);
    expect(inner.overrideStateId, 3);
    expect(session.requests, [0, 3]);
    expect(starts, 1);
  });

  test('Hidden API 明确不支持后撤销能力，当前连接不反复启动 Helper', () async {
    final adb = _FoldableAdb();
    var starts = 0;
    final service = _service(
      adb,
      factory: () async {
        starts++;
        throw FoldableScreenError.unsupported;
      },
    );
    addTearDown(service.dispose);
    expect(await service.probe(), isNotNull);
    await expectLater(
      service.select(FoldableScreen.outer),
      throwsA(FoldableScreenError.unsupported),
    );
    expect(await service.refresh(), isNull);
    expect(await service.probe(), isNull);
    expect(starts, 1);
  });

  test('恢复自动模式只重置自身请求并跟随真实基础姿态', () async {
    final adb = _FoldableAdb();
    final session = _FoldableSession(adb);
    final service = _service(adb, factory: () async => session);
    addTearDown(service.dispose);
    await service.select(FoldableScreen.outer);
    final snapshot = await service.restoreAutomatic();
    expect(session.resets, 1);
    expect(snapshot.currentScreen, FoldableScreen.inner);
    expect(snapshot.hasOverride, isFalse);
    expect(service.ownsOverride, isFalse);
  });

  test('已有外部覆盖时切换与恢复自动均不启动或取消其他 Helper', () async {
    final adb = _FoldableAdb()..overrideState = 5;
    var starts = 0;
    final service = _service(
      adb,
      factory: () async {
        starts++;
        return _FoldableSession(adb);
      },
    );
    addTearDown(service.dispose);
    await expectLater(
      service.select(FoldableScreen.outer),
      throwsA(FoldableScreenError.busyExternal),
    );
    await expectLater(
      service.restoreAutomatic(),
      throwsA(FoldableScreenError.busyExternal),
    );
    expect(starts, 0);
    expect(adb.overrideState, 5);
  });

  test('Helper 命令成功但 committed 状态未变化时超时并 close 回滚', () async {
    final adb = _FoldableAdb();
    final session = _FoldableSession(adb)..applyCommitted = false;
    final service = _service(adb, factory: () async => session);
    addTearDown(service.dispose);
    await expectLater(
      service.select(FoldableScreen.outer),
      throwsA(FoldableScreenError.timeout),
    );
    expect(session.requests, [0]);
    expect(session.closes, 1);
    expect(service.ownsOverride, isFalse);
    expect(adb.overrideState, isNull);
    expect(adb.committed, adb.baseState);
  });

  test('committed 与 override 已变化但物理屏未点亮时仍超时回滚', () async {
    final adb = _FoldableAdb()..physicalScreen = FoldableScreen.inner;
    final session = _FoldableSession(adb);
    final service = _service(adb, factory: () async => session);
    addTearDown(service.dispose);
    await expectLater(
      service.select(FoldableScreen.outer),
      throwsA(FoldableScreenError.timeout),
    );
    expect(session.closes, 1);
    expect(adb.overrideState, isNull);
  });

  test('物理屏已点亮但 logical display 0 仍指向旧屏时不误报成功', () async {
    final adb = _FoldableAdb()..primaryScreen = FoldableScreen.inner;
    final session = _FoldableSession(adb);
    final service = _service(adb, factory: () async => session);
    addTearDown(service.dispose);
    await expectLater(
      service.select(FoldableScreen.outer),
      throwsA(FoldableScreenError.timeout),
    );
    expect(session.closes, 1);
  });

  test('sessionFactory 迟到时 dispose 会关闭返回会话且不发送切屏请求', () async {
    final adb = _FoldableAdb();
    final session = _FoldableSession(adb);
    final entered = Completer<void>();
    final factory = Completer<FoldableScreenSession>();
    final service = _service(
      adb,
      factory: () {
        entered.complete();
        return factory.future;
      },
    );
    final selecting = expectLater(
      service.select(FoldableScreen.outer),
      throwsA(FoldableScreenError.unavailable),
    );
    await entered.future;
    await service.dispose();
    factory.complete(session);
    await selecting;
    expect(session.requests, isEmpty);
    expect(session.closes, 1);
    expect(adb.overrideState, isNull);
  });

  test('释放过程中再次 select 必须等待旧 Helper 关闭再建立新会话', () async {
    final adb = _FoldableAdb();
    final sessions = <_FoldableSession>[];
    final service = _service(
      adb,
      factory: () async {
        final session = _FoldableSession(adb);
        sessions.add(session);
        return session;
      },
    );
    addTearDown(service.dispose);
    await service.select(FoldableScreen.outer);
    final oldSession = sessions.single;
    oldSession.closeGate = Completer<void>();
    final releasing = service.release();
    await oldSession.closeEntered.future;
    final selecting = service.select(FoldableScreen.inner);
    await Future<void>.delayed(Duration.zero);
    expect(sessions.length, 1);
    oldSession.closeGate!.complete();
    await releasing;
    final selected = await selecting;
    expect(sessions.length, 2);
    expect(oldSession.closes, 1);
    expect(sessions.last.requests, [3]);
    expect(selected.currentScreen, FoldableScreen.inner);
  });

  test('request 在途遇到 release 时迟到响应失效且不遗留覆盖', () async {
    final adb = _FoldableAdb();
    final session = _FoldableSession(adb)..requestGate = Completer<void>();
    final service = _service(adb, factory: () async => session);
    addTearDown(service.dispose);
    final selecting = expectLater(
      service.select(FoldableScreen.outer),
      throwsA(FoldableScreenError.unavailable),
    );
    await session.requestEntered.future;
    await service.release();
    session.requestGate!.complete();
    await selecting;
    expect(session.closes, 1);
    expect(service.ownsOverride, isFalse);
    expect(adb.overrideState, isNull);
  });
}

/// 每次验证最多等待几十毫秒，完全隔离真机和真实 Helper 进程。
FoldableScreenService _service(
  _FoldableAdb adb, {
  FoldableSessionFactory? factory,
}) => FoldableScreenService(
  adb,
  'test-device',
  sessionFactory: factory ?? () async => _FoldableSession(adb),
  verificationTimeout: const Duration(milliseconds: 30),
  settleInterval: const Duration(milliseconds: 1),
);

/// 从同一份物理屏/布局证据生成实时状态，不通过真实 ADB 读取设备。
class _FoldableAdb extends AdbService {
  _FoldableAdb() : super(executable: 'unused-adb');

  final commands = <String>[];
  final timeouts = <Duration>[];
  final failures = <String, AdbResult>{};
  String states = foldableScreenStates;
  bool permission = true;
  int committed = 3;
  int baseState = 3;
  int? overrideState;
  FoldableScreen? physicalScreen;
  FoldableScreen? primaryScreen;

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final command = args.join(' ');
    commands.add(command);
    timeouts.add(timeout);
    final failure = failures[command];
    if (failure != null) return failure;
    final stdout = switch (command) {
      'cmd device_state print-states' => states,
      'cmd device_state state' =>
        "Committed state: DeviceState{identifier=$committed, name='CURRENT'}\n"
            '${overrideState == null ? '' : "Override state: DeviceState{identifier=$overrideState, name='OVERRIDE'}\n"}',
      'dumpsys display' => _display(),
      'dumpsys package com.android.shell' =>
        'android.permission.CONTROL_DEVICE_STATE: granted=$permission',
      _ => throw StateError('Unexpected command: $command'),
    };
    return AdbResult(exitCode: 0, stdout: stdout, stderr: '');
  }

  String _display() {
    final selected = committed == 0
        ? FoldableScreen.outer
        : FoldableScreen.inner;
    final physical = physicalScreen ?? selected;
    final primary = primaryScreen ?? selected;
    final primaryId = primary == FoldableScreen.inner
        ? '4630947004648141459'
        : '4630947123231501204';
    final lines = foldableScreenDisplayDump.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains('DisplayDeviceInfo{') ||
          !lines[i].contains('type INTERNAL')) {
        continue;
      }
      final isInner = lines[i].contains('local:4630947004648141459');
      final active = isInner == (physical == FoldableScreen.inner);
      lines[i] = lines[i].replaceAll(
        RegExp(r'\bstate (?:ON|OFF)\b'),
        'state ${active ? 'ON' : 'OFF'}',
      );
    }
    return '${lines.join('\n')}\nLogicalDisplayMapper:\n'
        '  Logical Displays: size=2\n'
        '  Display 0:\n'
        '    mDisplayId=0\n'
        '    mPrimaryDisplayDevice=内置屏幕(local:$primaryId)\n';
  }
}

/// 模拟 Binder 请求所有权与关闭回滚，并通过 gate 精确覆盖生命周期竞争。
class _FoldableSession implements FoldableScreenSession {
  _FoldableSession(this.adb);

  final _FoldableAdb adb;
  final requests = <int>[];
  final requestEntered = Completer<void>();
  final closeEntered = Completer<void>();
  Completer<void>? requestGate;
  Completer<void>? closeGate;
  bool applyCommitted = true;
  bool _ownsOverride = false;
  bool _closed = false;
  int resets = 0;
  int closes = 0;

  @override
  bool get ownsOverride => _ownsOverride && !_closed;

  @override
  Future<void> requestState(int stateId) async {
    requests.add(stateId);
    if (!requestEntered.isCompleted) requestEntered.complete();
    await requestGate?.future;
    if (_closed) return;
    _ownsOverride = true;
    adb.overrideState = stateId;
    if (applyCommitted) adb.committed = stateId;
  }

  @override
  Future<void> reset() async {
    resets++;
    _restore();
  }

  @override
  Future<void> close() async {
    closes++;
    if (!closeEntered.isCompleted) closeEntered.complete();
    await closeGate?.future;
    _restore();
    _closed = true;
  }

  void _restore() {
    _ownsOverride = false;
    adb.overrideState = null;
    adb.committed = adb.baseState;
  }
}
