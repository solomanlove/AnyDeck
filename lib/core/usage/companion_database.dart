import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'companion_history.dart';
import 'usage_snapshot.dart';

/// SQLite 持久化历史；每次操作在工作 Isolate 打开/释放连接，避免阻塞 UI。
class CompanionDatabase {
  const CompanionDatabase(this.path);
  final String path;

  static Future<CompanionDatabase> openDefault() async {
    final directory = await getApplicationSupportDirectory();
    return CompanionDatabase('${directory.path}/companion/history.sqlite');
  }

  Future<T> _run<T>(T Function(Database) action) {
    final databasePath = path;
    return Isolate.run(() {
      File(databasePath).parent.createSync(recursive: true);
      final db = sqlite3.open(databasePath);
      try {
        db.execute('PRAGMA busy_timeout=5000');
        db.execute('PRAGMA journal_mode=WAL');
        db.execute('''CREATE TABLE IF NOT EXISTS records (
          installation TEXT NOT NULL, user_id INTEGER NOT NULL, kind TEXT NOT NULL,
          record_id INTEGER NOT NULL, recorded_at INTEGER NOT NULL, day_key INTEGER,
          payload TEXT NOT NULL,
          PRIMARY KEY (installation,user_id,kind,record_id))''');
        db.execute('''CREATE TABLE IF NOT EXISTS cursors (
          installation TEXT NOT NULL, user_id INTEGER NOT NULL, kind TEXT NOT NULL,
          cursor INTEGER NOT NULL, gap INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY(installation,user_id,kind))''');
        db.execute(
          '''CREATE TABLE IF NOT EXISTS routes (
          route TEXT PRIMARY KEY, installation TEXT NOT NULL, user_id INTEGER NOT NULL)''',
        );
        return action(db);
      } finally {
        db.dispose();
      }
    });
  }

  Future<int> cursor(CompanionSource source, String kind) => _run((db) {
    final rows = db.select(
      'SELECT cursor FROM cursors WHERE installation=? AND user_id=? AND kind=?',
      [source.installationId, source.androidUserId, kind],
    );
    return rows.isEmpty ? 0 : rows.first['cursor'] as int;
  });

  /// 保留 v0.1 的真实本地快照，以保留编号 0 导入，不推进手机同步游标。
  Future<void> migrateLegacy(String route, UsageSnapshot snapshot) =>
      _run((db) {
        db.execute('BEGIN IMMEDIATE');
        try {
          db.execute('INSERT OR IGNORE INTO records VALUES (?,?,?,?,?,?,?)', [
            snapshot.installationId,
            snapshot.androidUserId,
            'usage',
            0,
            snapshot.generatedAtMs,
            snapshot.requestedStartMs,
            jsonEncode(snapshot.json),
          ]);
          db.execute('INSERT OR IGNORE INTO routes VALUES (?,?,?)', [
            route,
            snapshot.installationId,
            snapshot.androidUserId,
          ]);
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      });

  /// 记录与游标在同一事务提交，重复页幂等，失败不推进游标。
  Future<void> importPage(String route, CompanionPage page) => _run((db) {
    final source = page.source;
    final key = [source.installationId, source.androidUserId, page.kind];
    db.execute('BEGIN IMMEDIATE');
    try {
      final current = db.select(
        'SELECT cursor FROM cursors WHERE installation=? AND user_id=? AND kind=?',
        key,
      );
      final cursor = current.isEmpty ? 0 : current.first['cursor'] as int;
      if (page.after > cursor) {
        throw const UsageSyncException('historyCursorInvalid');
      }
      for (final row in page.records) {
        final data = row['data'] as Map<String, dynamic>;
        db.execute('INSERT OR IGNORE INTO records VALUES (?,?,?,?,?,?,?)', [
          ...key,
          row['id'],
          row['recordedAtMs'],
          page.kind == 'usage' ? data['requestedStartMs'] : null,
          jsonEncode(data),
        ]);
      }
      final gap = page.firstAvailableId > page.after + 1 ? 1 : 0;
      db.execute(
        '''INSERT INTO cursors VALUES (?,?,?,?,?) ON CONFLICT(installation,user_id,kind)
        DO UPDATE SET cursor=MAX(cursor,excluded.cursor), gap=MAX(gap,excluded.gap)''',
        [...key, page.nextCursor, gap],
      );
      db.execute('INSERT OR REPLACE INTO routes VALUES (?,?,?)', [
        route,
        source.installationId,
        source.androidUserId,
      ]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  });

  Future<CompanionHistoryView> load(String route) async {
    final result = await _run((db) {
      final routes = db.select('SELECT * FROM routes WHERE route=?', [route]);
      if (routes.isEmpty) return <String, dynamic>{};
      final identity = routes.first;
      final key = [identity['installation'], identity['user_id']];
      final usage = db.select(
        '''SELECT payload FROM records WHERE installation=? AND user_id=?
        AND kind='usage' AND record_id IN (
          SELECT MAX(record_id) FROM records WHERE installation=? AND user_id=? AND kind='usage'
          GROUP BY day_key ORDER BY MAX(record_id) DESC LIMIT 30)
        ORDER BY record_id DESC''',
        [...key, ...key],
      );
      final locations = db.select(
        '''SELECT payload FROM records WHERE installation=? AND user_id=?
        AND kind='location' ORDER BY record_id DESC LIMIT 10000''',
        key,
      );
      final gaps = db.select(
        'SELECT MAX(gap) AS gap FROM cursors WHERE installation=? AND user_id=?',
        key,
      );
      return <String, dynamic>{
        'usage': usage.map((row) => row['payload'] as String).toList(),
        'locations': locations.map((row) => row['payload'] as String).toList(),
        'gap': gaps.first['gap'] == 1,
        'installationId': key[0],
        'androidUserId': key[1],
      };
    });
    if (result.isEmpty) return const CompanionHistoryView();
    return CompanionHistoryView(
      source: CompanionSource.fromJson(result),
      usage: (result['usage'] as List)
          .map((row) => UsageSnapshot.fromJson(jsonDecode(row)))
          .toList(),
      locations: (result['locations'] as List)
          .map((row) => LocationRecord.fromJson(jsonDecode(row)))
          .toList(),
      hasGap: result['gap'] as bool,
    );
  }

  /// 删除当前来源的电脑历史与游标；手机数据保留，下次可重新导入尚未过期的记录。
  Future<void> clear(String route) => _run((db) {
    final rows = db.select('SELECT * FROM routes WHERE route=?', [route]);
    if (rows.isEmpty) return;
    final key = [rows.first['installation'], rows.first['user_id']];
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final table in ['records', 'cursors', 'routes']) {
        db.execute(
          'DELETE FROM $table WHERE installation=? AND user_id=?',
          key,
        );
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  });
}

/// 桌面最近 30 个查询日的最终快照与最多 10000 个位置点。
class CompanionHistoryView {
  const CompanionHistoryView({
    this.usage = const [],
    this.locations = const [],
    this.hasGap = false,
    this.source,
  });
  final List<UsageSnapshot> usage;
  final List<LocationRecord> locations;
  final bool hasGap;
  final CompanionSource? source;
}
