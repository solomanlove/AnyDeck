import 'dart:async';
import 'dart:io';
import 'package:any_deck/core/nearby_share/harmony_share_outbox.dart';
import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:flutter_test/flutter_test.dart';

ShareSendBatch batch(
  String id, [
  ShareSendStatus status = ShareSendStatus.queued,
]) => ShareSendBatch(
  id: id,
  transferredBytes: 0,
  items: [
    ShareSendItem(
      id: '$id-file',
      status: status,
      peer: ShareCorePeer(
        address: InternetAddress.loopbackIPv4,
        port: 1234,
        name: 'fixture',
      ),
      file: ShareSendFile(
        file: File('/synthetic/$id'),
        bytes: 1,
        modified: DateTime(2026),
      ),
    ),
  ],
);
Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('保存中关闭仍完成 idle，不启动会话或回调已销毁监听', () async {
    final saved = Completer<void>();
    var calls = 0;
    var notices = 0;
    final outbox = HarmonyShareOutbox(
      persist: (_) => saved.future,
      execute: (item) async {
        calls++;
        return item;
      },
      cancelActive: () {},
      changed: (_) {},
    );
    outbox.addListener(() => notices++);
    final accepted = outbox.enqueue(batch('closing'));
    outbox.dispose();
    final before = notices;
    saved.complete();
    await accepted;
    await outbox.idle;
    expect(calls, 0);
    expect(notices, before);
  });

  test('持久化前不启动，严格 FIFO，某批失败后继续下一批', () async {
    final saved = Completer<void>();
    final transfer = Completer<ShareSendBatch>();
    final calls = <String>[];
    final outbox = HarmonyShareOutbox(
      persist: (item) => item.id == '1' ? saved.future : Future.value(),
      execute: (item) {
        calls.add(item.id);
        return item.id == '1'
            ? transfer.future
            : Future.value(batch(item.id, ShareSendStatus.succeeded));
      },
      cancelActive: () {},
      changed: (_) {},
    );
    final first = outbox.enqueue(batch('1'));
    await outbox.enqueue(batch('2'));
    expect(calls, isEmpty);
    saved.complete();
    await first;
    await tick();
    expect(calls, ['1']);
    transfer.complete(batch('1', ShareSendStatus.failed));
    await outbox.idle;
    expect(calls, ['1', '2']);
    expect(outbox.succeeded, 1);
    expect(outbox.failed, 1);
    expect(outbox.running, isFalse);
    outbox.dispose();
  });
  test('待发取消与保存竞态写终态，整体取消阻止追加', () async {
    final save = Completer<void>();
    final transfer = Completer<ShareSendBatch>();
    final changes = <String>[];
    var calls = 0;
    final outbox = HarmonyShareOutbox(
      persist: (item) => item.id == '2' ? save.future : Future.value(),
      execute: (item) {
        calls++;
        return transfer.future;
      },
      cancelActive: () =>
          transfer.complete(batch('1', ShareSendStatus.cancelled)),
      changed: (item) => changes.add('${item.id}:${item.status.name}'),
    );
    await outbox.enqueue(batch('1'));
    final pending = outbox.enqueue(batch('2'));
    outbox.cancel('2');
    expect(changes, isEmpty);
    save.complete();
    await pending;
    expect(changes, ['2:cancelled']);
    outbox.cancelAll();
    outbox.cancelAll();
    await expectLater(outbox.enqueue(batch('3')), throwsStateError);
    await outbox.idle;
    expect(calls, 1);
    expect(outbox.cancelled, 2);
    outbox.dispose();
  });
  test('容量有界，已完成项可让位，整体结果不会因精简展示而丢失', () async {
    final transfers = <Completer<ShareSendBatch>>[];
    final outbox = HarmonyShareOutbox(
      persist: (_) async {},
      execute: (_) {
        final done = Completer<ShareSendBatch>();
        transfers.add(done);
        return done.future;
      },
      cancelActive: () {},
      changed: (_) {},
    );
    for (var i = 0; i < 8; i++) {
      await outbox.enqueue(batch('$i'));
    }
    await expectLater(outbox.enqueue(batch('full')), throwsStateError);
    transfers.first.complete(batch('0', ShareSendStatus.succeeded));
    await tick();
    await outbox.enqueue(batch('8'));
    expect(outbox.entries.length, 8);
    for (var i = 1; i < 9; i++) {
      await tick();
      transfers[i].complete(batch('$i', ShareSendStatus.succeeded));
    }
    await outbox.idle;
    expect(outbox.succeeded, 9);
    outbox.clear();
    expect(outbox.entries, isEmpty);
    outbox.dispose();
  });
  test('保存失败不发送，执行异常释放调度器，不阻断后续批次', () async {
    var calls = 0;
    final outbox = HarmonyShareOutbox(
      persist: (item) async {
        if (item.id == 'bad') throw StateError('history_buffer_full');
      },
      execute: (_) async {
        calls++;
        throw StateError('network');
      },
      cancelActive: () {},
      changed: (_) {},
    );
    await expectLater(outbox.enqueue(batch('bad')), throwsStateError);
    await outbox.idle;
    expect(calls, 0);
    expect(outbox.failed, 1);
    await outbox.enqueue(batch('ok'));
    await outbox.idle;
    expect(calls, 1);
    expect(outbox.failed, 1);
    outbox.dispose();
  });
}
