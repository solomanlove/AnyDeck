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
}
