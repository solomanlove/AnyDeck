import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'share_transfer_record.dart';

/// 鸿蒙互联独立 SQLite；每次操作在工作 Isolate 打开连接，避免阻塞 Flutter UI。
class ShareHistoryDatabase {
  const ShareHistoryDatabase(this.path);
  final String path;
  static Future<ShareHistoryDatabase> openDefault() async {
    final directory = await getApplicationSupportDirectory();
    return ShareHistoryDatabase(
      '${directory.path}/harmony_share/history.sqlite',
    );
  }

  Future<T> _run<T>(T Function(Database) action) {
    final databasePath = path;
    return Isolate.run(() {
      File(databasePath).parent.createSync(recursive: true);
      final db = sqlite3.open(databasePath);
      try {
        db.execute('PRAGMA busy_timeout=5000');
        db.execute('PRAGMA journal_mode=WAL');
        db.execute('''CREATE TABLE IF NOT EXISTS transfers (
          id TEXT PRIMARY KEY, direction TEXT NOT NULL, status TEXT NOT NULL,
          device_name TEXT NOT NULL, address TEXT NOT NULL, port INTEGER,
          file_name TEXT NOT NULL, path TEXT, bytes INTEGER NOT NULL,
          transferred_bytes INTEGER NOT NULL, created_at INTEGER NOT NULL,
          completed_at INTEGER, error TEXT, sha256 TEXT, retry_of TEXT
        )''');
        // 兼容升级前的记录库；同一工作连接内迁移，不改旧记录含义。
        final columns = db.select('PRAGMA table_info(transfers)').map((row) => row['name']).toSet();
        if (!columns.contains('file_count')) db.execute('ALTER TABLE transfers ADD COLUMN file_count INTEGER NOT NULL DEFAULT 1');
        if (!columns.contains('batch_id')) db.execute('ALTER TABLE transfers ADD COLUMN batch_id TEXT');
        if (!columns.contains('progress_known')) db.execute('ALTER TABLE transfers ADD COLUMN progress_known INTEGER NOT NULL DEFAULT 0');
        if (!columns.contains('file_index')) db.execute('ALTER TABLE transfers ADD COLUMN file_index INTEGER');
        db.execute('CREATE INDEX IF NOT EXISTS idx_transfer_batch ON transfers(batch_id)');
        db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transfer_time ON transfers(created_at DESC, id DESC)',
        );
        db.execute(
          'CREATE INDEX IF NOT EXISTS idx_transfer_sort ON transfers(COALESCE(completed_at,created_at) DESC,id DESC)',
        );
        return action(db);
      } finally {
        db.dispose();
      }
    });
  }

  /// 一个 batch 的排队记录原子写入，进程中断后仍能看到未完成项。
  Future<void> save(List<ShareTransferRecord> records) => _run((db) {
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final record in records) {
        final map = record.toMap();
        final columns = map.keys.join(',');
        final updates = map.keys
            .where((key) => key != 'id')
            .map((key) => '$key=excluded.$key')
            .join(',');
        db.execute(
          'INSERT INTO transfers ($columns) VALUES (${List.filled(map.length, '?').join(',')}) ON CONFLICT(id) DO UPDATE SET $updates',
          map.values.toList(),
        );
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  });

  /// 重启只将悬挂任务标为中断，不自动重发文件或自动接受来件。
  Future<void> recoverInterrupted() => _run((db) {
    db.execute(
      "UPDATE transfers SET status='interrupted', completed_at=? WHERE status IN ('queued','preparing','transferring','awaitingAcceptance')",
      [DateTime.now().millisecondsSinceEpoch],
    );
  });

  /// 使用时间/id 游标分页，新增记录不会导致旧页偏移或重复。
  Future<List<ShareTransferRecord>> query({
    ShareTransferDirection? direction,
    String search = '',
    ShareTransferRecord? before,
    int limit = 100,
  }) => _run((db) {
    if (limit < 1 || limit > 200) throw ArgumentError.value(limit, 'limit');
    final where = <String>[if (search.isEmpty) 'batch_id IS NULL'];
    final args = <Object?>[];
    if (direction != null) {
      where.add('direction=?');
      args.add(direction.name);
    }
    if (search.isNotEmpty) {
      final escaped = search
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      where.add(
        "(file_name LIKE ? ESCAPE '\\' OR device_name LIKE ? ESCAPE '\\')",
      );
      args.addAll(['%$escaped%', '%$escaped%']);
    }
    if (before != null) {
      where.add(
        '(COALESCE(completed_at,created_at) < ? OR (COALESCE(completed_at,created_at) = ? AND id < ?))',
      );
      args.addAll([
        before.sortTime.millisecondsSinceEpoch,
        before.sortTime.millisecondsSinceEpoch,
        before.id,
      ]);
    }
    final rows = db.select(
      'SELECT * FROM transfers ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY COALESCE(completed_at,created_at) DESC, id DESC LIMIT ?',
      [...args, limit],
    );
    return rows.map((row) => ShareTransferRecord.fromMap(row)).toList();
  });

  /// 子文件不挤占首页摘要；仅在查看整批详情时加载有界清单。
  Future<List<ShareTransferRecord>> batchFiles(String id) => _run((db) => db.select(
    'SELECT * FROM transfers WHERE batch_id=? ORDER BY file_index,id LIMIT 100', [id],
  ).map((row) => ShareTransferRecord.fromMap(row)).toList());

  /// 仅移除终态记录，绝不删除磁盘文件，也不隐藏正在执行的任务。
  Future<void> remove(String id) => _run((db) {
    db.execute(
      "DELETE FROM transfers WHERE (id=? OR batch_id=?) AND status NOT IN ('queued','preparing','transferring','awaitingAcceptance')",
      [id, id],
    );
  });
}
