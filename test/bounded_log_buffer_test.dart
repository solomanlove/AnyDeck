import 'package:any_deck/core/logcat/bounded_log_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证日志突发输出时的多重预算和最近尾部保留。
void main() {
  test('突发日志同时受条数、单行和总字符预算约束', () {
    final buffer = BoundedLogBuffer(
      maxLines: 3,
      maxLineLength: 5,
      maxCharacters: 8,
    );
    buffer.addAll(['123456789', 'abc', 'last']);
    expect(buffer.lines, ['abc', 'last']);
    expect(buffer.characters, 7);
    for (var i = 0; i < 10000; i++) {
      buffer.add('$i');
    }
    expect(buffer.length, lessThanOrEqualTo(3));
    expect(buffer.characters, lessThanOrEqualTo(8));
    expect(buffer.lines.last, '9999');
    buffer.clear();
    expect(buffer.characters, 0);
    expect(buffer.isEmpty, isTrue);
  });
}
