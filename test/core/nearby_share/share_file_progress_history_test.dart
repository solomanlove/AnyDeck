import 'dart:io';

import 'package:any_deck/core/nearby_share/share_file_progress.dart';
import 'package:any_deck/core/nearby_share/share_history_database.dart';
import 'package:any_deck/core/nearby_share/share_transfer_history.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  for (final success in [false, true]) {
    test('接收部分文件字节${success ? "最终完整成功" : "失败后保留"}，序号/已知标记可重新读取', () async {
      final root = await Directory.systemTemp.createTemp(
        'file-progress-history-',
      );
      final db = ShareHistoryDatabase('${root.path}/history.sqlite');
      final history = ShareTransferHistory(
        open: () async => db,
        maxPendingRecords: 4,
      );
      try {
        await history.initialize();
        final id = history.incoming(
          address: '192.168.1.3',
          name: 'fixture',
          bytes: 12,
          fileCount: 3,
        );
        history.receiveChanged(id, status: ShareTransferStatus.transferring);
        history.receivedFileProgress(
          id,
          const ShareCoreFileProgress(
            index: 2,
            direction: 'receive',
            bytes: 2,
            totalBytes: 5,
          ),
        );
        history.receivedFileProgress(
          id,
          const ShareCoreFileProgress(
            index: 2,
            direction: 'receive',
            bytes: 1,
            totalBytes: 5,
          ),
        );
        history.receivedFileProgress(
          id,
          const ShareCoreFileProgress(
            index: 3,
            direction: 'receive',
            bytes: 1,
            totalBytes: 1,
          ),
        );
        history.receiveChanged(
          id,
          status: success
              ? ShareTransferStatus.cancelled
              : ShareTransferStatus.failed,
        );
        await history.flush();
        final partial = (await db.batchFiles(id)).single;
        expect((await db.query()).single.progressKnown, isTrue);
        expect(partial.fileIndex, 2);
        expect(partial.fileName, isEmpty);
        expect(partial.path, isNull);
        expect(partial.progressKnown, isTrue);
        expect(partial.transferredBytes, 2);
        expect(
          partial.status,
          success ? ShareTransferStatus.cancelled : ShareTransferStatus.failed,
        );
        if (success) {
          expect(
            history.receivedBatch(id, [
              for (var i = 0; i < 3; i++)
                {
                  'path': '${root.path}/file-$i',
                  'bytes': i + 3,
                  'sha256': 'a' * 64,
                },
            ], root.path),
            isTrue,
          );
          await history.flush();
          final files = await db.batchFiles(id);
          expect(files.map((file) => file.fileIndex), [0, 1, 2]);
          expect(files.map((file) => file.transferredBytes), [3, 4, 5]);
          expect(
            files.every(
              (file) =>
                  file.progressKnown &&
                  file.status == ShareTransferStatus.succeeded,
            ),
            isTrue,
          );
        }
        final again = ShareHistoryDatabase(db.path);
        expect((await again.batchFiles(id)).last.progressKnown, isTrue);
        // 终态后容量预留已释放，未知文件不会占据额外虚构槽位。
        history.incoming(address: '192.168.1.3', name: 'next', bytes: 1);
        await history.flush();
        expect(history.error, isNull);
      } finally {
        await history.flush();
        history.dispose();
        await root.delete(recursive: true);
      }
    });
  }
  test('部分文件检查点写入故障整批回滚，恢复后准确补写已知进度', () async {
    final root = await Directory.systemTemp.createTemp(
      'file-progress-failure-',
    );
    final db = ShareHistoryDatabase('${root.path}/history.sqlite');
    final history = ShareTransferHistory(open: () async => db);
    try {
      await history.initialize();
      final id = history.incoming(
        address: '192.168.1.3',
        name: 'fixture',
        bytes: 7,
        fileCount: 2,
      );
      history.receiveChanged(id, status: ShareTransferStatus.transferring);
      await history.flush();
      final raw = sqlite3.open(db.path);
      raw.execute(
        "CREATE TRIGGER fail_progress BEFORE INSERT ON transfers WHEN NEW.batch_id IS NOT NULL BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      );
      raw.dispose();
      history.receivedFileProgress(
        id,
        const ShareCoreFileProgress(
          index: 1,
          direction: 'receive',
          bytes: 2,
          totalBytes: 4,
        ),
      );
      history.receiveChanged(id, status: ShareTransferStatus.failed);
      await history.flush();
      expect(history.error, isNotNull);
      expect(await db.batchFiles(id), isEmpty);
      expect(
        (await db.query()).single.status,
        ShareTransferStatus.transferring,
      );
      final repaired = sqlite3.open(db.path);
      repaired.execute('DROP TRIGGER fail_progress');
      repaired.dispose();
      expect(await history.retryPending(), isTrue);
      final saved = (await db.batchFiles(id)).single;
      expect(saved.transferredBytes, 2);
      expect(saved.progressKnown, isTrue);
      expect(saved.status, ShareTransferStatus.failed);
      expect((await db.query()).single.transferredBytes, 2);
    } finally {
      await history.flush();
      history.dispose();
      await root.delete(recursive: true);
    }
  });
}
