import 'package:any_deck/core/terminal/adb_terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _terminalProvider =
    NotifierProvider<AdbTerminalNotifier, AdbTerminalState>(
      AdbTerminalNotifier.new,
    );

void main() {
  test('鸿蒙终端将完整命令作为单次 HDC shell 参数发送', () {
    expect(
      harmonyShellArguments(
        '192.168.31.83:5555',
        "hidumper -s WindowManagerService -a '-a'",
      ),
      [
        '-t',
        '192.168.31.83:5555',
        'shell',
        "hidumper -s WindowManagerService -a '-a'",
      ],
    );
  });

  test('鸿蒙终端空回车换行，不执行 HDC 命令或写入命令历史', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final terminal = container.read(_terminalProvider.notifier);
    await terminal.createSession('harmony-device', isHarmony: true);
    final sessionId = container
        .read(_terminalProvider)
        .getActiveSession('harmony-device')!
        .id;

    terminal.sendCommand('harmony-device', sessionId, '');
    terminal.sendCommand('harmony-device', sessionId, '');

    final session = container
        .read(_terminalProvider)
        .getActiveSession('harmony-device')!;
    expect(session.lines.map((line) => line.text), [r'$ ', r'$ ', '']);
    expect(session.commandHistory, isEmpty);
  });

  test('终端命令历史与单行输出保持有界', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final terminal = container.read(_terminalProvider.notifier);
    await terminal.createSession('harmony-device', isHarmony: true);
    final sessionId = container
        .read(_terminalProvider)
        .getActiveSession('harmony-device')!
        .id;
    terminal.suspendDevice('harmony-device');

    for (var i = 0; i < 205; i++) {
      terminal.sendCommand('harmony-device', sessionId, 'command$i');
    }
    terminal.sendCommand('harmony-device', sessionId, 'x' * 20000);

    final session = container
        .read(_terminalProvider)
        .getActiveSession('harmony-device')!;
    expect(session.commandHistory, hasLength(200));
    expect(session.commandHistory.first, 'command6');
    expect(session.commandHistory.last.length, 16384);
    expect(session.lines.last.text.length, lessThanOrEqualTo(16384));
  });

  test('快速创建的会话 ID 保持唯一', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final terminal = container.read(_terminalProvider.notifier);
    await terminal.createSession('harmony-device', isHarmony: true);
    await terminal.createSession('harmony-device', isHarmony: true);

    final sessions = container
        .read(_terminalProvider)
        .getSessions('harmony-device');
    expect(sessions.map((session) => session.id).toSet(), hasLength(2));
  });
}
