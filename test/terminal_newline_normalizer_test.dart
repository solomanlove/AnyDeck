import 'package:any_deck/core/terminal/terminal_newline_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 覆盖 MIX3 PTY 的真实换行格式，以及网络拆包后的提示符显示。
void main() {
  const normalizer = TerminalNewlineNormalizer();

  test('MIX3 的提权、目录切换和退出记录不产生重复空行', () async {
    final chunks = [
      'perseus:/ \$ ',
      'su\r\r\nperseus:/ # ',
      'id\r\r\nuid=0(root)\r\nperseus:/ # ',
      'cd /data/local/tmp\r\r\nperseus:/data/local/tmp # ',
      'exit\r\r\nperseus:/ \$ ',
    ];
    final result = await Stream.fromIterable(
      chunks,
    ).transform(normalizer).join();
    expect(
      result,
      'perseus:/ \$ su\nperseus:/ # id\nuid=0(root)\n'
      'perseus:/ # cd /data/local/tmp\nperseus:/data/local/tmp # exit\n'
      'perseus:/ \$ ',
    );
  });

  test('CRCRLF 在任意位置拆包，结果与完整输出一致', () async {
    const transcript = 'su\r\r\nroot:/ # id\r\nuid=0(root)\n\nroot:/ # ';
    const expected = 'su\nroot:/ # id\nuid=0(root)\n\nroot:/ # ';
    for (var split = 0; split <= transcript.length; split++) {
      final result = await Stream.fromIterable([
        transcript.substring(0, split),
        transcript.substring(split),
      ]).transform(normalizer).join();
      expect(result, expected, reason: 'split=$split');
    }
  });

  test('无换行提示符立即输出，中文和已有空行保持不变', () async {
    final result = await Stream.fromIterable([
      'root:/ # ',
      '中文目录\n\n',
    ]).transform(normalizer).toList();
    expect(result, ['root:/ # ', '中文目录\n\n']);
  });

  test('每个会话使用独立的换行状态', () async {
    expect(await Stream.value('one\r').transform(normalizer).join(), 'one\n');
    expect(await Stream.value('\ntwo').transform(normalizer).join(), '\ntwo');
  });
}
