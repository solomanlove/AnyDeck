import 'package:any_deck/core/nearby_share/share_file_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> event(int index, int done, int total) => {
    'event': 'file_progress',
    'direction': 'receive',
    'index': index,
    'bytes': done,
    'total_bytes': total,
  };
  test('文件独立单调与大小核对，乱序到达不分摊总量', () {
    final ledger = ShareFileProgressLedger(
      count: 2,
      bytes: 7,
      direction: 'receive',
    );
    ledger.accept(event(1, 2, 4));
    ledger.accept(event(0, 3, 3));
    expect(ledger.snapshots.map((file) => file.bytes), [3, 2]);
    final old = ledger.snapshots;
    ledger.accept(event(1, 4, 4));
    expect(old.last.bytes, 2);
    expect(() => old.clear(), throwsUnsupportedError);
    expect(() => ledger.accept(event(1, 3, 4)), throwsFormatException);
    expect(() => ledger.accept(event(1, 4, 5)), throwsFormatException);
    expect(() => ledger.checkResult(1, 3), throwsFormatException);
    ledger.checkResult(1, 4);
  });
  test('拒绝索引/类型/方向/大小与不可能的总量，坏事件不改变已知值', () {
    final ledger = ShareFileProgressLedger(
      count: 2,
      bytes: 7,
      direction: 'receive',
    );
    for (final bad in [
      event(-1, 1, 3),
      event(2, 1, 3),
      event(0, 4, 3),
      event(0, -1, 3),
      event(0, 1, 7),
      {...event(0, 1, 3), 'index': 0.5},
      {...event(0, 1, 3), 'bytes': true},
      {...event(0, 1, 3), 'direction': 'send'},
    ]) {
      expect(() => ledger.accept(bad), throwsFormatException);
      expect(ledger.snapshots, isEmpty);
    }
    ledger.accept(event(0, 1, 3));
    expect(() => ledger.accept(event(1, 1, 3)), throwsFormatException);
    ledger.accept(event(1, 1, 4));
    expect(ledger.snapshots.length, 2);
  });
  test('发送精确声明和100 GiB算术边界；不创建实际大文件', () {
    const gib = 1073741824;
    final ledger = ShareFileProgressLedger(
      count: 100,
      bytes: 100 * gib,
      direction: 'send',
      sizes: List.filled(100, gib),
    );
    for (var index = 99; index >= 0; index--) {
      ledger.accept({...event(index, gib, gib), 'direction': 'send'});
    }
    expect(
      ledger.snapshots.fold<int>(0, (sum, file) => sum + file.bytes),
      100 * gib,
    );
    expect(
      () => ShareFileProgressLedger(
        count: 2,
        bytes: 7,
        direction: 'send',
        sizes: [3, 3],
      ),
      throwsFormatException,
    );
    expect(
      () => ledger.accept({...event(0, gib, gib - 1), 'direction': 'send'}),
      throwsFormatException,
    );
  });
}
