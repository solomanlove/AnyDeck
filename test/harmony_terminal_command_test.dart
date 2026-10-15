import 'package:any_deck/core/terminal/adb_terminal_session.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
