import 'package:any_deck/core/nearby_share/share_transfer_rate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'dart:io';
import 'package:fake_async/fake_async.dart';
import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';

void main() {
  test('速率过期自动刷新后停止唤醒，批次结束和 dispose 不遗留 Timer', () {
    fakeAsync((clock) {
      final tracker = ShareTransferRate(elapsed: () => clock.elapsed);
      final done = Completer<void>();
      late void Function(ShareCoreProgress) progress;
      var notices = 0;
      final queue = HarmonyShareSendQueue(
        rateTracker: tracker,
        send: (_, _) async {},
        sendBatch: (_, callback) {
          progress = callback;
          return done.future;
        },
        cancelActive: () {},
      );
      queue.addListener(() => notices++);
      unawaited(
        queue.run(
          ShareCorePeer(
            address: InternetAddress.loopbackIPv4,
            port: 1234,
            name: 'fixture',
          ),
          ShareSendSelection([
            ShareSendFile(
              file: File('/synthetic/file'),
              bytes: 1000,
              modified: DateTime(2026),
            ),
          ]),
        ),
      );
      clock.flushMicrotasks();
      progress(
        const ShareCoreProgress(direction: 'send', bytes: 0, totalBytes: 1000),
      );
      clock.elapse(const Duration(seconds: 1));
      progress(
        const ShareCoreProgress(
          direction: 'send',
          bytes: 100,
          totalBytes: 1000,
        ),
      );
      expect(queue.rate, isNotNull);
      clock.elapse(const Duration(seconds: 4));
      expect(queue.rate, isNull);
      final staleNotices = notices;
      clock.elapse(const Duration(seconds: 10));
      expect(notices, staleNotices);
      done.complete();
      clock.flushMicrotasks();
      expect(queue.rate, isNull);
      queue.dispose();
      clock.elapse(const Duration(seconds: 10));
    });
  });

  test('真实字节增量估算当前批次，准备和单样本没有虚构速度', () {
    var now = Duration.zero;
    final rate = ShareTransferRate(elapsed: () => now);
    expect(rate.estimate, isNull);
    rate.observe(200, 2000);
    expect(rate.estimate, isNull);
    now = const Duration(seconds: 2);
    rate.observe(1200, 2000);
    expect(rate.estimate!.bytesPerSecond, 500);
    expect(rate.estimate!.remaining.inSeconds, 2);
    now = const Duration(seconds: 6);
    expect(rate.estimate, isNull);
    rate.observe(1400, 2000);
    expect(rate.estimate, isNull);
    now = const Duration(seconds: 7);
    rate.observe(1500, 2000);
    expect(rate.estimate!.bytesPerSecond, 100);
    rate.observe(2000, 2000);
    expect(rate.estimate, isNull);
    rate.reset();
    expect(rate.estimate, isNull);
  });
  test('高频样本有界并使用近期速度，忽略回退、错误总量和时钟倒退', () {
    var now = Duration.zero;
    final rate = ShareTransferRate(elapsed: () => now);
    var bytes = 0;
    for (var i = 0; i <= 2000; i++) {
      now = Duration(milliseconds: i * 10);
      bytes += i < 500 ? 100 : 1;
      rate.observe(bytes, 1000000);
    }
    expect(rate.estimate!.bytesPerSecond, closeTo(100, 1));
    final before = rate.estimate!.bytesPerSecond;
    rate.observe(bytes - 1, 1000000);
    rate.observe(bytes + 1, 1);
    rate.observe(-1, 1000000);
    now = const Duration(seconds: 10);
    rate.observe(bytes + 10, 1000000);
    now = const Duration(seconds: 20);
    expect(rate.estimate!.bytesPerSecond, before);
  });
  test('零增量不估算剩余，重置后不混入上一批', () {
    var now = Duration.zero;
    final rate = ShareTransferRate(elapsed: () => now);
    rate.observe(0, 100);
    now = const Duration(seconds: 1);
    rate.observe(0, 100);
    expect(rate.estimate, isNull);
    rate.observe(50, 100);
    expect(rate.estimate, isNotNull);
    rate.reset();
    rate.observe(0, 1000);
    expect(rate.estimate, isNull);
  });
}
