import 'dart:async';
import 'package:any_deck/core/nearby_share/share_history_writer.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

ShareTransferRecord record(
  String id, {
  ShareTransferStatus status = ShareTransferStatus.queued,
  int count = 1,
  String? batch,
}) => ShareTransferRecord(
  id: id,
  batchId: batch,
  fileCount: count,
  direction: ShareTransferDirection.receive,
  status: status,
  deviceName: 'fixture',
  address: '127.0.0.1',
  fileName: id,
  bytes: count,
  createdAt: DateTime(2026),
);

void main() {
  test('失败后保留最新记录，后续新任务不能掩盖失败，显式重试合并事务', () {
    fakeAsync((clock) {
      var failing = true;
      final committed = <List<ShareTransferRecord>>[];
      final writer = ShareHistoryWriter(
        persist: (rows) async {
          if (failing) throw StateError('synthetic disk unavailable');
          committed.add(rows);
        },
        changed: () {},
      );
      unawaited(writer.save([record('old')]));
      clock.flushMicrotasks();
      expect(writer.error, isNotNull);
      unawaited(
        writer.save([record('old', status: ShareTransferStatus.succeeded)]),
      );
      unawaited(
        writer.save([record('new', status: ShareTransferStatus.failed)]),
      );
      clock.flushMicrotasks();
      expect(writer.pendingRecords, 2);
      expect(writer.error, isNotNull);
      failing = false;
      unawaited(writer.flush());
      clock.flushMicrotasks();
      expect(committed.single.map((row) => row.status), [
        ShareTransferStatus.succeeded,
        ShareTransferStatus.failed,
      ]);
      expect(writer.error, isNull);
      expect(writer.pendingRecords, 0);
      expect(writer.reservedRecords, 0);
      writer.dispose();
    });
  });

  test('存储恢复后自动补写并清除错误，无需新的传输事件', () {
    fakeAsync((clock) {
      var failing = true;
      final committed = <String>[];
      final writer = ShareHistoryWriter(
        persist: (rows) async {
          if (failing) throw StateError('synthetic unavailable');
          committed.addAll(rows.map((row) => row.id));
        },
        changed: () {},
      );
      unawaited(
        writer.save([record('auto', status: ShareTransferStatus.succeeded)]),
      );
      clock.flushMicrotasks();
      failing = false;
      clock.elapse(const Duration(seconds: 1));
      expect(committed, ['auto']);
      expect(writer.error, isNull);
      expect(writer.pendingRecords, 0);
      writer.dispose();
    });
  });

  test('预留 100 文件终态容量，容量满只拒绝新任务，不阻断既有批次', () {
    fakeAsync((clock) {
      final writer = ShareHistoryWriter(
        maxRecords: 101,
        persist: (_) async {},
        changed: () {},
      );
      unawaited(writer.save([record('batch', count: 100)]));
      clock.flushMicrotasks();
      expect(writer.pendingRecords, 0);
      expect(writer.reservedRecords, 101);
      expect(
        () => writer.save([record('other')]),
        throwsA(isA<ShareHistoryBufferFull>()),
      );
      unawaited(
        writer.save([
          record('batch', count: 100, status: ShareTransferStatus.succeeded),
          for (var i = 0; i < 100; i++)
            record('$i', batch: 'batch', status: ShareTransferStatus.succeeded),
        ]),
      );
      clock.flushMicrotasks();
      expect(writer.pendingRecords, 0);
      expect(writer.reservedRecords, 0);
      unawaited(
        writer.save([record('other', status: ShareTransferStatus.failed)]),
      );
      clock.flushMicrotasks();
      writer.dispose();
    });
  });

  test('在途写入不删除较新终态，写入严格串行', () {
    fakeAsync((clock) {
      final gate = Completer<void>();
      final saved = <ShareTransferStatus>[];
      var active = 0;
      final writer = ShareHistoryWriter(
        persist: (rows) async {
          expect(++active, 1);
          saved.add(rows.single.status);
          if (saved.length == 1) await gate.future;
          active--;
        },
        changed: () {},
      );
      unawaited(writer.save([record('one')]));
      clock.flushMicrotasks();
      unawaited(
        writer.save([record('one', status: ShareTransferStatus.succeeded)]),
      );
      expect(writer.pendingRecords, 1);
      gate.complete();
      clock.flushMicrotasks();
      expect(saved, [
        ShareTransferStatus.queued,
        ShareTransferStatus.succeeded,
      ]);
      expect(writer.pendingRecords, 0);
      writer.dispose();
    });
  });

  test('自动重试退避且有界，dispose 后不再写库或通知', () {
    fakeAsync((clock) {
      var attempts = 0;
      var notifications = 0;
      final writer = ShareHistoryWriter(
        persist: (_) async {
          attempts++;
          throw StateError('synthetic unavailable');
        },
        changed: () => notifications++,
      );
      unawaited(writer.save([record('one')]));
      clock.flushMicrotasks();
      for (var i = 0; i < 100; i++) {
        unawaited(writer.save([record('one')]));
      }
      clock.flushMicrotasks();
      expect(attempts, 1);
      for (final seconds in [1, 2, 5, 10, 30, 30]) {
        final before = attempts;
        clock.elapse(Duration(seconds: seconds - 1));
        expect(attempts, before);
        clock.elapse(const Duration(seconds: 1));
        expect(attempts, before + 1);
      }
      writer.dispose();
      final lastNotifications = notifications;
      clock.elapse(const Duration(minutes: 5));
      expect(attempts, 7);
      expect(notifications, lastNotifications);
    });
  });

  test('错误清单或多余子文件不能绕过容量，也不部分加入新任务', () {
    fakeAsync((clock) {
      final gate = Completer<void>();
      final writer = ShareHistoryWriter(
        maxRecords: 3,
        persist: (_) => gate.future,
        changed: () {},
      );
      unawaited(writer.save([record('batch', count: 2)]));
      expect(
        () => writer.save([
          for (var i = 0; i < 3; i++) record('$i', batch: 'batch'),
        ]),
        throwsStateError,
      );
      expect(
        () => writer.save([record('orphan', batch: 'missing')]),
        throwsStateError,
      );
      expect(writer.pendingRecords, 1);
      expect(writer.reservedRecords, 3);
      writer.dispose();
      gate.complete();
      clock.flushMicrotasks();
    });
  });
}
