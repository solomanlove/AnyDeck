import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_process_service.dart';
import 'package:any_deck/core/ios/ios_process_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// 仅模拟主机 CLI 的双流、退出与取消，不启动设备命令。
class _Process implements Process {
  _Process(this.output, {this.error = '', this.code = 0, this.hang = false});
  final String output, error;
  final int code;
  final bool hang;
  bool killed = false;
  final ended = Completer<int>();
  @override
  Stream<List<int>> get stdout => Stream.value(utf8.encode(output));
  @override
  Stream<List<int>> get stderr => Stream.value(utf8.encode(error));
  @override
  Future<int> get exitCode => hang ? ended.future : Future.value(code);
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!ended.isCompleted) ended.complete(-1);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Commands extends IosCommandService {
  final calls = <List<String>>[];
  String processes =
      '[{"Pid":42,"Name":"App","RealAppName":"/Applications/A.app/App","StartDate":"2026-10-05T10:00:00Z","IsApplication":true},{"Pid":1,"Name":"launchd","IsApplication":false}]';
  String apps =
      '[{"CFBundleIdentifier":"com.example.app","CFBundleDisplayName":"Example","ApplicationType":"User","Path":"/Applications/A.app"}]';
  bool failApps = false;
  _Process? custom;
  Completer<Process>? starting;
  @override
  Future<Process> start(List<String> args) async {
    calls.add(args);
    if (starting != null) return starting!.future;
    return custom ??
        _Process(
          args.first == 'apps' ? apps : processes,
          code: args.first == 'apps' && failApps ? 1 : 0,
        );
  }
}

void main() {
  test('查询全进程，不传 --apps；3 秒刷新不重查元数据', () async {
    final commands = _Commands();
    final service = IosProcessService(commands, 'device-a');
    addTearDown(service.close);
    final items = await service.read();
    expect(items.singleWhere((p) => p.pid == 42).app?.name, 'Example');
    expect(items.singleWhere((p) => p.pid == 1).app, isNull);
    await service.read();
    expect(commands.calls, [
      ['ps', '--udid=device-a'],
      ['apps', '--all', '--udid=device-a'],
      ['ps', '--udid=device-a'],
    ]);
    await service.read(refreshApps: true);
    expect(commands.calls.where((args) => args.first == 'apps'), hasLength(2));
  });

  test('元数据失败保留旧关联，损坏进程输出显式失败', () async {
    final commands = _Commands();
    final service = IosProcessService(commands, 'a');
    addTearDown(service.close);
    await service.read();
    commands.failApps = true;
    expect((await service.read(refreshApps: true)).first.app?.name, 'Example');
    expect(service.metadataError, isNotNull);
    commands.processes = '{"level":"WARN","msg":"warning only"}';
    await expectLater(service.read(), throwsFormatException);
  });

  test('PID 重用或退出不发 kill，身份一致才路由指定 UDID', () async {
    final commands = _Commands();
    final service = IosProcessService(commands, 'a');
    addTearDown(service.close);
    final app = (await service.read()).first;
    await service.kill(app);
    expect(commands.calls.last, ['kill', '--pid=42', '--udid=a']);
    commands.calls.clear();
    commands.processes =
        '[{"Pid":42,"Name":"App","RealAppName":"/Applications/A.app/App","StartDate":"2026-10-06T10:00:00Z"}]';
    await expectLater(service.kill(app), throwsA(isA<IosProcessChanged>()));
    expect(commands.calls.any((args) => args.first == 'kill'), isFalse);
    commands.processes = '[]';
    await expectLater(service.kill(app), throwsA(isA<IosProcessChanged>()));
  });

  test('exit 0 的 fatal/error 日志按失败处理；WARN 允许正常 JSON', () async {
    final commands = _Commands()
      ..custom = _Process('[]', error: '{"level":"error","msg":"denied"}');
    final session = IosProcessSession(commands);
    addTearDown(session.close);
    expect((await session.run(['ps'])).isSuccess, isFalse);
    commands.custom = _Process('[]', error: '{"level":"WARN","msg":"agent"}');
    expect((await session.run(['ps'])).isSuccess, isTrue);
  });

  test('超时主动终止 CLI，并限制输出大小', () async {
    final process = _Process('', hang: true);
    final commands = _Commands()..custom = process;
    final session = IosProcessSession(commands);
    addTearDown(session.close);
    await expectLater(
      session.run(['ps'], timeout: const Duration(milliseconds: 10)),
      throwsA(isA<TimeoutException>()),
    );
    expect(process.killed, isTrue);
    commands.custom = _Process('x' * (8 * 1024 * 1024 + 1));
    await expectLater(session.run(['ps']), throwsStateError);
    expect(commands.custom!.killed, isTrue);
  });

  test('离页取消尚未完成的 start，返回后立即终止；禁止后续命令', () async {
    final commands = _Commands()..starting = Completer<Process>();
    final session = IosProcessSession(commands);
    final pending = session.run(['ps']);
    session.close();
    final process = _Process('[]', hang: true);
    commands.starting!.complete(process);
    await expectLater(pending, throwsStateError);
    expect(process.killed, isTrue);
    await expectLater(session.run(['kill']), throwsStateError);
    expect(commands.calls, hasLength(1));
  });
}
