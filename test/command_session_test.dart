import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/process/command_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_process.dart';

/// 用可控双流验证超时、取消、输出预算与单次在途，不执行真实命令。
void main() {
  test('双流均被消费，重复调用不启动第二个进程', () async {
    final process = ControlledProcess();
    var starts = 0;
    final session = CommandSession(
      startProcess: (_, _) async {
        starts++;
        return process;
      },
    );
    final first = session.run('fake', []);
    expect(identical(first, session.run('fake', [])), isTrue);
    await Future<void>.delayed(Duration.zero);
    process.output.add(utf8.encode('正常'));
    process.errors.add(utf8.encode('辅助'));
    process.finish();
    final result = await first;
    expect(starts, 1);
    expect(result.stdout, '正常');
    expect(result.stderr, '辅助');
  });

  test('超时主动杀进程并返回 124', () async {
    final process = ControlledProcess();
    final session = CommandSession(startProcess: (_, _) async => process);
    final result = await session.run(
      'fake',
      [],
      timeout: const Duration(milliseconds: 20),
    );
    expect(result.exitCode, 124);
    expect(process.signals, contains(ProcessSignal.sigkill));
  });

  test('销毁期间迟到启动的进程也被回收', () async {
    final starting = Completer<Process>();
    final session = CommandSession(startProcess: (_, _) => starting.future);
    final result = session.run('fake', []);
    session.close();
    final process = ControlledProcess();
    starting.complete(process);
    await expectLater(result, throwsStateError);
    expect(process.signals, isNotEmpty);
  });

  test('stdout/stderr 合计超限时终止并报告错误', () async {
    final process = ControlledProcess();
    final session = CommandSession(startProcess: (_, _) async => process);
    final result = session.run('fake', [], maxOutputBytes: 8);
    final failure = expectLater(result, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    process.output.add(List.filled(6, 65));
    process.errors.add(List.filled(6, 66));
    await failure;
    expect(process.signals, isNotEmpty);
  });
}
