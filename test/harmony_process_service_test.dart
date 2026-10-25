import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/process/process_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHdcService extends HdcService {
  _FakeHdcService(this.topResult) : super(executable: 'hdc');

  final AdbResult topResult;
  final commands = <String>[];

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(command);
    if (command == 'top -b -n 1') return topResult;
    return const AdbResult(
      exitCode: 0,
      stdout: 'UID PID PPID C STIME TTY TIME CMD\n20006 2604 1 0 10:00 ? 00:00:06 com.huawei.hmos.location\n',
      stderr: '',
    );
  }
}

void main() {
  test('鸿蒙进程从 top 快照读取 CPU 与 RES 内存', () async {
    final hdc = _FakeHdcService(const AdbResult(
      exitCode: 0,
      stdout: '''Tasks: 170 total
   PID USER PR NI VIRT RES SHR S[%CPU] %MEM TIME+ ARGS
  2604 20006 20 0 2.1G 27M 24M S 3.5 0.2 0:06.12 com.huawei.hmos.location
''',
      stderr: '',
    ));
    final service = ProcessService(AdbService(executable: 'adb'), hdc);

    final processes = await service.getProcesses('harmony-device', isHarmony: true);

    expect(processes, hasLength(1));
    expect(processes.single.cpu, '3.5');
    expect(processes.single.memory, '27M');
    expect(processes.single.name, 'com.huawei.hmos.location');
    expect(hdc.commands, ['top -b -n 1']);
  });

  test('top 不可用时回退 ps 进程列表', () async {
    final hdc = _FakeHdcService(const AdbResult(exitCode: 1, stdout: '', stderr: 'unsupported'));
    final service = ProcessService(AdbService(executable: 'adb'), hdc);

    final processes = await service.getProcesses('harmony-device', isHarmony: true);

    expect(processes.single.pid, '2604');
    expect(hdc.commands, ['top -b -n 1', 'ps -ef']);
  });
}
