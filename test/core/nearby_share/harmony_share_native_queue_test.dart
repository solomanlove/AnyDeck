import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:flutter_test/flutter_test.dart';

final peer = ShareCorePeer(
  address: InternetAddress('192.168.1.3'),
  port: 44800,
  name: 'fixture',
);
ShareSendSelection selection(int count) => ShareSendSelection([
  for (var i = 0; i < count; i++)
    ShareSendFile(
      file: File('/synthetic/$i.bin'),
      bytes: 1024 * 1024 * 1024,
      modified: DateTime(2026),
    ),
]);
Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('100 文件一次批次，不分摊总进度，严格校验进度并等最终成功', () async {
    final done = Completer<void>();
    final secondDone = Completer<void>();
    late void Function(ShareCoreProgress) progress;
    var calls = 0;
    final queue = HarmonyShareSendQueue(
      send: (_, _) => throw StateError('legacy'),
      sendBatch: (items, callback) {
        expect(items.length, calls == 0 ? 100 : 1);
        calls++;
        progress = callback;
        return calls == 1 ? done.future : secondDone.future;
      },
      cancelActive: () {},
    );
    final run = queue.run(peer, selection(100));
    await tick();
    final total = queue.totalBytes;
    progress(
      ShareCoreProgress(
        direction: 'send',
        bytes: total ~/ 2,
        totalBytes: total,
      ),
    );
    expect(queue.transferredBytes, total ~/ 2);
    expect(queue.items.every((item) => item.transferredBytes == 0), isTrue);
    expect(queue.count(ShareSendStatus.transferring), 100);
    for (final update in [
      ShareCoreProgress(direction: 'receive', bytes: total, totalBytes: total),
      ShareCoreProgress(direction: 'send', bytes: total, totalBytes: total - 1),
      ShareCoreProgress(direction: 'send', bytes: 1, totalBytes: total),
      ShareCoreProgress(direction: 'send', bytes: total + 1, totalBytes: total),
    ]) {
      progress(update);
    }
    expect(queue.transferredBytes, total ~/ 2);
    progress(
      ShareCoreProgress(direction: 'send', bytes: total, totalBytes: total),
    );
    expect(queue.finished, 0);
    done.complete();
    await run;
    expect(calls, 1);
    expect(queue.count(ShareSendStatus.succeeded), 100);
    final oldProgress = progress;
    final second = queue.run(peer, selection(1));
    await tick();
    oldProgress(
      ShareCoreProgress(
        direction: 'send',
        bytes: queue.totalBytes,
        totalBytes: queue.totalBytes,
      ),
    );
    expect(queue.transferredBytes, 0);
    secondDone.complete();
    await second;
    expect(queue.items.single.status, ShareSendStatus.succeeded);
    expect(queue.transferredBytes, queue.totalBytes);
    queue.clear();
    queue.dispose();
    oldProgress(
      const ShareCoreProgress(direction: 'send', bytes: 0, totalBytes: 1),
    );
  });

  for (final success in [true, false]) {
    test('取消任一文件作用整批，取消幂等，晚到有效成功优先 $success', () async {
      final done = Completer<void>();
      var cancels = 0;
      final queue = HarmonyShareSendQueue(
        send: (_, _) async {},
        sendBatch: (_, _) => done.future,
        cancelActive: () => cancels++,
      );
      final run = queue.run(peer, selection(3));
      await tick();
      queue.cancel(queue.items[1].id);
      queue.cancelAll();
      expect(cancels, 1);
      expect(queue.cancelling, isTrue);
      if (success) {
        done.complete();
      } else {
        done.completeError(StateError('cancelled'));
      }
      await run;
      expect(
        queue.count(
          success ? ShareSendStatus.succeeded : ShareSendStatus.cancelled,
        ),
        3,
      );
      expect(queue.cancelling, isFalse);
      queue.dispose();
    });
  }

  test('初次落盘期间取消不会启动网络；新批次可以重用', () async {
    final writing = Completer<void>();
    var calls = 0;
    final queue = HarmonyShareSendQueue(
      send: (_, _) async {},
      sendBatch: (_, _) async => calls++,
      onBatchQueued: (_) => writing.future,
      cancelActive: () {},
    );
    final run = queue.run(peer, selection(2));
    queue.cancelAll();
    writing.complete();
    await run;
    expect(calls, 0);
    expect(queue.count(ShareSendStatus.cancelled), 2);
    await queue.run(peer, selection(1));
    expect(calls, 1);
    expect(queue.count(ShareSendStatus.succeeded), 1);
    queue.dispose();
  });

  test('批次失败不会回退到逐项发送或自动重试', () async {
    var calls = 0;
    final queue = HarmonyShareSendQueue(
      send: (_, _) => throw StateError('legacy'),
      sendBatch: (_, progress) async {
        calls++;
        progress(
          const ShareCoreProgress(
            direction: 'send',
            bytes: 10,
            totalBytes: 3221225472,
          ),
        );
        throw StateError('phone rejected');
      },
      cancelActive: () {},
    );
    await queue.run(peer, selection(3));
    expect(calls, 1);
    expect(queue.count(ShareSendStatus.failed), 3);
    expect(queue.transferredBytes, 10);
    expect(
      queue.items.every((item) => item.error!.contains('phone rejected')),
      isTrue,
    );
    queue.dispose();
  });
}
