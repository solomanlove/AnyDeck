import 'dart:io';
import 'package:any_deck/core/nearby_share/share_history_database.dart';
import 'package:any_deck/core/nearby_share/share_transfer_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('旧 SQLite 库原地迁移，批次摘要与子文件独立检索/级联删除', () async {
    final root = await Directory.systemTemp.createTemp('batch-migration-');
    final path = '${root.path}/history.sqlite';
    final old = sqlite3.open(path);
    old.execute(
      'CREATE TABLE transfers(id TEXT PRIMARY KEY,direction TEXT,status TEXT,device_name TEXT,address TEXT,port INTEGER,file_name TEXT,path TEXT,bytes INTEGER,transferred_bytes INTEGER,created_at INTEGER,completed_at INTEGER,error TEXT,sha256 TEXT,retry_of TEXT)',
    );
    old.execute(
      "INSERT INTO transfers(id,direction,status,device_name,address,file_name,bytes,transferred_bytes,created_at) VALUES('old','receive','succeeded','old peer','1.2.3.4','old.bin',1,1,1)",
    );
    old.dispose();
    final db = ShareHistoryDatabase(path);
    final history = ShareTransferHistory(open: () async => db);
    try {
      await history.initialize();
      expect(history.recent.single.fileCount, 1);
      expect(history.recent.single.progressKnown, isFalse);
      expect(history.recent.single.fileIndex, isNull);
      final id = history.incoming(
        address: '1.2.3.4',
        name: 'peer',
        bytes: 7,
        fileCount: 2,
      );
      final files = [
        for (var i = 0; i < 2; i++)
          {
            'path': '${root.path}/file-$i.bin',
            'bytes': i + 3,
            'sha256': 'a' * 64,
          },
      ];
      history.receivedBatch(id, files, root.path);
      await history.flush();
      expect((await db.query()).length, 2);
      expect((await db.batchFiles(id)).length, 2);
      expect((await db.batchFiles(id)).map((file) => file.fileIndex), [0, 1]);
      expect((await db.batchFiles(id)).every((file) => file.progressKnown), isTrue);
      expect((await db.query(search: 'file-0')).single.batchId, id);
      await db.remove(id);
      expect((await db.query()).single.id, 'old');
      expect(await db.batchFiles(id), isEmpty);
    } finally {
      await history.flush();
      history.dispose();
      await root.delete(recursive: true);
    }
  });
}
