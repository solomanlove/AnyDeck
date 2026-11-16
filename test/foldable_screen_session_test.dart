import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/foldable/foldable_screen_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟 adb 的 stdin/stdout 与退出时序，不启动进程或改变真机状态。
class _HelperProcess implements Process {
  _HelperProcess({bool ready = true, int version = 1}) {
    stdin = IOSink(_input.sink);
    _input.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final command = jsonDecode(line) as Map<String, dynamic>;
          commands.add(command);
          if (command['command'] == 'state' && exitOnState) {
            finish();
            return;
          }
          emit({
            'id': command['id'],
            'ok': command['command'] != 'state' || failureCode == null,
            if (failureCode != null) 'code': failureCode,
          });
          if (command['command'] == 'close') scheduleMicrotask(finish);
        }, onDone: finish);
    if (ready) {
      scheduleMicrotask(() => emit({'ready': true, 'version': version}));
    }
  }

  final _input = StreamController<List<int>>();
  final _output = StreamController<List<int>>();
  final _errors = StreamController<List<int>>();
  final _exit = Completer<int>();
  final commands = <Map<String, dynamic>>[];
  String? failureCode;
  bool exitOnState = false;

  void emit(Map<String, dynamic> message) {
    if (!_output.isClosed) _output.add(utf8.encode('${jsonEncode(message)}\n'));
  }

  void finish() {
    if (_exit.isCompleted) return;
    _output.close();
    _errors.close();
    _exit.complete(0);
  }

  @override
  late final IOSink stdin;
  @override
  Stream<List<int>> get stdout => _output.stream;
  @override
  Stream<List<int>> get stderr => _errors.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 1;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    finish();
    return true;
  }
}

void main() {
  test('握手不切屏，请求、取消与关闭按 JSON 协议执行', () async {
    final process = _HelperProcess();
    final session = await AdbFoldableScreenSession.connect(process);
    expect(process.commands, isEmpty);
    expect(session.ownsOverride, isFalse);
    await session.requestState(7);
    expect(session.ownsOverride, isTrue);
    expect(process.commands.single['state'], 7);
    await session.reset();
    expect(session.ownsOverride, isFalse);
    await session.close();
    await session.close();
    expect(process.commands.map((value) => value['command']), [
      'state',
      'reset',
      'close',
    ]);
  });

  test('仅匹配当前目标的取消事件释放本地所有权', () async {
    final process = _HelperProcess();
    final session = await AdbFoldableScreenSession.connect(process);
    await session.requestState(9);
    process.emit({'event': 'canceled', 'state': 7});
    await Future<void>.delayed(Duration.zero);
    expect(session.ownsOverride, isTrue);
    process.emit({'event': 'canceled', 'state': 9});
    await Future<void>.delayed(Duration.zero);
    expect(session.ownsOverride, isFalse);
    await session.close();
  });

  for (final code in ['busy', 'external_override']) {
    test('设备占用 $code 映射独立提示，不能认领请求', () async {
      final process = _HelperProcess()..failureCode = code;
      final session = await AdbFoldableScreenSession.connect(process);
      await expectLater(
        session.requestState(0),
        throwsA(FoldableScreenError.busyExternal),
      );
      expect(session.ownsOverride, isFalse);
      await session.close();
    });
  }

  test('请求中设备进程退出，立即结束等待并释放所有权', () async {
    final process = _HelperProcess()..exitOnState = true;
    final session = await AdbFoldableScreenSession.connect(process);
    await expectLater(
      session.requestState(0),
      throwsA(FoldableScreenError.unavailable),
    );
    expect(session.ownsOverride, isFalse);
    await session.close();
  });

  test('设备明确不支持请求时区分临时断线', () async {
    final process = _HelperProcess()..failureCode = 'unsupported';
    final session = await AdbFoldableScreenSession.connect(process);
    await expectLater(
      session.requestState(0),
      throwsA(FoldableScreenError.unsupported),
    );
    expect(session.ownsOverride, isFalse);
    await session.close();
  });

  test('握手超时关闭 stdin 和进程，不发送状态请求', () async {
    final process = _HelperProcess(ready: false);
    await expectLater(
      AdbFoldableScreenSession.connect(
        process,
        timeout: const Duration(milliseconds: 5),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(await process.exitCode, 0);
    expect(process.commands, isEmpty);
  });

  test('协议版本不匹配时停止会话', () async {
    final process = _HelperProcess(version: 2);
    await expectLater(
      AdbFoldableScreenSession.connect(process),
      throwsA(FoldableScreenError.failed),
    );
    expect(
      process.commands.where((command) => command['command'] == 'state'),
      isEmpty,
    );
  });
}
