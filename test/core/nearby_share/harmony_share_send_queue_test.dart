import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:flutter_test/flutter_test.dart';

final _peer = ShareCorePeer(
  address: InternetAddress('192.168.1.2'),
  port: 44800,
  name: 'nova',
);
ShareSendSelection _selection([int count = 3]) => ShareSendSelection([
  for (var i = 0; i < count; i++)
    ShareSendFile(
      file: File('/synthetic/$i.bin'),
      bytes: 10,
      modified: DateTime(2026),
    ),
]);
Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('严格串行，100%字节不替代核心最终完成，汇总不提前增加成功数', () async {
    final pending = <Completer<void>>[];
    final callbacks = <void Function(ShareCoreProgress)>[];
    final queue = HarmonyShareSendQueue(
      send: (item, progress) {
        callbacks.add(progress);
        final result = Completer<void>();
        pending.add(result);
        return result.future;
      },
      cancelActive: () {},
    );
    final running = queue.run(_peer, _selection(2));
    expect(pending.length, 1);
    callbacks.first(
      const ShareCoreProgress(direction: 'send', bytes: 10, totalBytes: 10),
    );
    expect(queue.finished, 0);
    expect(queue.current!.status, ShareSendStatus.transferring);
    pending.first.complete();
    await _tick();
    expect(pending.length, 2);
    expect(queue.count(ShareSendStatus.succeeded), 1);
    expect(queue.totalBytes, 20);
    expect(queue.transferredBytes, 10);
    pending.last.complete();
    await running;
    expect(queue.transferredBytes, 20);
    expect(queue.finished, 2);
    expect(queue.running, isFalse);
    queue.dispose();
  });

  test('单项失败保留原因，继续后续项目', () async {
    var calls = 0;
    final queue = HarmonyShareSendQueue(
      send: (item, _) async {
        if (calls++ == 0) throw StateError('phone rejected');
      },
      cancelActive: () {},
    );
    await queue.run(_peer, _selection());
    expect(calls, 3);
    expect(queue.items.first.error, contains('phone rejected'));
    expect(queue.count(ShareSendStatus.failed), 1);
    expect(queue.count(ShareSendStatus.succeeded), 2);
    expect(queue.transferredBytes, 20);
    queue.dispose();
  });

  test('取消排队文件不影响活动项，取消活动项后继续剩余', () async {
    final active = Completer<void>();
    var calls = 0;
    var cancels = 0;
    final queue = HarmonyShareSendQueue(
      send: (_, _) {
        calls++;
        return calls == 1 ? active.future : Future.value();
      },
      cancelActive: () {
        cancels++;
        active.completeError(StateError('cancelled'));
      },
    );
    final running = queue.run(_peer, _selection());
    queue.cancel(queue.items[1].id);
    expect(cancels, 0);
    expect(queue.items[1].status, ShareSendStatus.cancelled);
    queue.cancel(queue.items.first.id);
    await running;
    expect(cancels, 1);
    expect(calls, 2);
    expect(queue.count(ShareSendStatus.cancelled), 2);
    expect(queue.items.last.status, ShareSendStatus.succeeded);
    queue.dispose();
  });

  test('整队取消后不再开始后续文件', () async {
    final active = Completer<void>();
    var calls = 0;
    final queue = HarmonyShareSendQueue(
      send: (_, _) {
        calls++;
        return active.future;
      },
      cancelActive: () => active.completeError(StateError('cancelled')),
    );
    final running = queue.run(_peer, _selection());
    queue.cancelAll();
    await running;
    expect(calls, 1);
    expect(queue.count(ShareSendStatus.cancelled), 3);
    queue.clear();
    expect(queue.items, isEmpty);
    queue.dispose();
  });

  test('错误总量、倒退进度和迟到回调不能污染任务', () async {
    final active = Completer<void>();
    late void Function(ShareCoreProgress) progress;
    final queue = HarmonyShareSendQueue(
      send: (_, callback) {
        progress = callback;
        return active.future;
      },
      cancelActive: () {},
    );
    final running = queue.run(_peer, _selection(1));
    progress(
      const ShareCoreProgress(direction: 'send', bytes: 5, totalBytes: 10),
    );
    for (final update in [
      const ShareCoreProgress(direction: 'send', bytes: 9, totalBytes: 11),
      const ShareCoreProgress(direction: 'send', bytes: 3, totalBytes: 10),
      const ShareCoreProgress(direction: 'receive', bytes: 9, totalBytes: 10),
      const ShareCoreProgress(direction: 'send', bytes: -1, totalBytes: 10),
    ]) {
      progress(update);
    }
    expect(queue.transferredBytes, 5);
    active.complete();
    await running;
    progress(
      const ShareCoreProgress(direction: 'send', bytes: 1, totalBytes: 10),
    );
    expect(queue.transferredBytes, 10);
    expect(queue.items.single.status, ShareSendStatus.succeeded);
    queue.dispose();
  });

  test('运行中不能被第二批覆盖，完成后新批次可重用', () async {
    final active = Completer<void>();
    final queue = HarmonyShareSendQueue(
      send: (_, _) => active.future,
      cancelActive: () {},
    );
    final first = queue.run(_peer, _selection(1));
    final id = queue.items.first.id;
    await expectLater(queue.run(_peer, _selection()), throwsStateError);
    expect(queue.items.single.id, id);
    queue.clear();
    expect(queue.items.length, 1);
    active.complete();
    await first;
    await queue.run(_peer, _selection(1));
    expect(queue.items.single.id, isNot(id));
    queue.dispose();
  });

  test('迟到的取消不覆盖已由核心完成的成功结果，重复取消保持幂等', () async {
    final done = Completer<void>();
    var cancels = 0;
    final queue = HarmonyShareSendQueue(
      send: (_, _) => done.future,
      cancelActive: () => cancels++,
    );
    final running = queue.run(_peer, _selection(1));
    queue.cancel(queue.items.single.id);
    queue.cancel(queue.items.single.id);
    expect(cancels, 1);
    done.complete();
    await running;
    expect(queue.items.single.status, ShareSendStatus.succeeded);
    expect(queue.transferredBytes, 10);
    queue.dispose();
  });

  test('选择去重、排队期间改变文件及目录/链接/空文件边界', () async {
    final root = await Directory.systemTemp.createTemp('anydeck-queue-test-');
    try {
      final file = await File(
        '${root.path}/synthetic.bin',
      ).writeAsBytes([1, 2]);
      final selection = await ShareSendSelection.inspect([file, file]);
      expect(selection.files.length, 1);
      expect(selection.bytes, 2);
      await file.writeAsBytes([1, 2, 3]);
      await expectLater(
        selection.files.single.verifyUnchanged(),
        throwsA(isA<FileSystemException>()),
      );
      final empty = await File('${root.path}/empty').create();
      await expectLater(
        ShareSendSelection.inspect([empty]),
        throwsFormatException,
      );
      await expectLater(
        ShareSendSelection.inspect([File(root.path)]),
        throwsFormatException,
      );
      if (!Platform.isWindows) {
        final link = await Link('${root.path}/link').create(file.path);
        await expectLater(
          ShareSendSelection.inspect([File(link.path)]),
          throwsFormatException,
        );
      }
      await expectLater(
        ShareSendSelection.inspect(List.filled(101, file)),
        throwsFormatException,
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
