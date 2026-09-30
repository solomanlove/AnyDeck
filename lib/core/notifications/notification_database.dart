import 'dart:io';
import 'dart:isolate';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'notification_models.dart';

/// 手机通知本地 SQLite 存储；每次操作在工作 Isolate 打开并释放连接。
class NotificationDatabase {
  const NotificationDatabase(this.path);
  final String path;

  static Future<NotificationDatabase> openDefault() async {
    final directory = await getApplicationSupportDirectory();
    return NotificationDatabase(
      '${directory.path}/companion/notifications.sqlite',
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
        db.execute('''CREATE TABLE IF NOT EXISTS notifications (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          installation TEXT NOT NULL,
          user_id INTEGER NOT NULL,
          notification_key TEXT NOT NULL,
          package_name TEXT NOT NULL,
          app_name TEXT,
          title TEXT,
          content TEXT,
          post_time INTEGER NOT NULL,
          received_time INTEGER NOT NULL,
          is_removed INTEGER NOT NULL DEFAULT 0
        )''');
        db.execute('''CREATE TABLE IF NOT EXISTS notification_sources (
          alias TEXT PRIMARY KEY,
          installation TEXT NOT NULL,
          user_id INTEGER NOT NULL,
          updated_time INTEGER NOT NULL
        )''');
        db.execute(
          '''CREATE INDEX IF NOT EXISTS idx_notif_lookup ON notifications(installation, user_id, notification_key)''',
        );
        db.execute(
          '''CREATE INDEX IF NOT EXISTS idx_notif_time ON notifications(installation, user_id, received_time DESC)''',
        );
        return action(db);
      } finally {
        db.dispose();
      }
    });
  }

  /// 插入或更新通知；同一 notificationKey 覆盖更新，并触发 7 天及 10000 条保留裁剪。
  Future<NotificationMessage> insertOrUpdate(NotificationMessage msg) =>
      _run((db) {
        db.execute('BEGIN IMMEDIATE');
        try {
          final existing = db.select(
            'SELECT id FROM notifications WHERE installation=? AND user_id=? AND notification_key=?',
            [msg.installationId, msg.androidUserId, msg.notificationKey],
          );

          final int messageId;
          if (existing.isNotEmpty) {
            messageId = existing.first['id'] as int;
            db.execute(
              '''UPDATE notifications SET title=?, content=?, app_name=?, post_time=?, received_time=?, is_removed=0
                 WHERE id=?''',
              [
                msg.title,
                msg.content,
                msg.appName,
                msg.postTime.millisecondsSinceEpoch,
                msg.receivedTime.millisecondsSinceEpoch,
                messageId,
              ],
            );
          } else {
            db.execute(
              '''INSERT INTO notifications (installation, user_id, notification_key, package_name, app_name, title, content, post_time, received_time, is_removed)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)''',
              [
                msg.installationId,
                msg.androidUserId,
                msg.notificationKey,
                msg.packageName,
                msg.appName,
                msg.title,
                msg.content,
                msg.postTime.millisecondsSinceEpoch,
                msg.receivedTime.millisecondsSinceEpoch,
              ],
            );
            messageId = db.lastInsertRowId;
          }

          // 自动裁剪 7 天前的历史数据
          final sevenDaysAgo =
              DateTime.now().millisecondsSinceEpoch - (7 * 24 * 3600 * 1000);
          db.execute(
            'DELETE FROM notifications WHERE received_time < ?',
            [sevenDaysAgo],
          );

          // 单设备上限 10000 条裁剪
          db.execute(
            '''DELETE FROM notifications WHERE installation = ? AND user_id = ? AND id NOT IN (
                 SELECT id FROM notifications WHERE installation = ? AND user_id = ? ORDER BY received_time DESC LIMIT 10000
               )''',
            [
              msg.installationId,
              msg.androidUserId,
              msg.installationId,
              msg.androidUserId,
            ],
          );

          db.execute('COMMIT');
          return msg.copyWith(id: messageId);
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      });

  /// 手机端移除通知时，标记为已移除但保留电脑端历史。
  Future<void> markAsRemoved(
    String installationId,
    int userId,
    String notificationKey,
  ) => _run((db) {
    db.execute(
      'UPDATE notifications SET is_removed=1 WHERE installation=? AND user_id=? AND notification_key=?',
      [installationId, userId, notificationKey],
    );
  });

  /// 分页及条件检索历史消息。
  Future<List<NotificationMessage>> queryMessages(
    String installationId,
    int userId, {
    String? query,
    String? packageName,
    int offset = 0,
    int limit = 50,
  }) => _run((db) {
    final where = <String>['installation = ?', 'user_id = ?'];
    final args = <dynamic>[installationId, userId];

    if (packageName != null && packageName.isNotEmpty) {
      where.add('package_name = ?');
      args.add(packageName);
    }
    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      where.add('(title LIKE ? OR content LIKE ? OR app_name LIKE ?)');
      args.addAll([q, q, q]);
    }

    final sql =
        '''SELECT id, installation, user_id, notification_key, package_name, app_name, title, content, post_time, received_time, is_removed
           FROM notifications
           WHERE ${where.join(' AND ')}
           ORDER BY received_time DESC
           LIMIT ? OFFSET ?''';
    args.addAll([limit, offset]);

    final rows = db.select(sql, args);
    return rows.map((r) => NotificationMessage.fromMap(r)).toList();
  });

  /// 清空指定设备的全部消息历史。
  Future<void> clearMessages(String installationId, int userId) => _run((db) {
    db.execute(
      'DELETE FROM notifications WHERE installation=? AND user_id=?',
      [installationId, userId],
    );
  });

  /// 保存 serial、USB/Wi-Fi route 到 Companion 安装实例的关联，供离线查询恢复来源。
  Future<void> linkSource(
    Iterable<String> aliases,
    String installationId,
    int userId,
  ) => _run((db) {
    final updatedTime = DateTime.now().millisecondsSinceEpoch;
    final statement = db.prepare(
      '''INSERT INTO notification_sources (alias, installation, user_id, updated_time)
             VALUES (?, ?, ?, ?)
             ON CONFLICT(alias) DO UPDATE SET installation=excluded.installation,
               user_id=excluded.user_id, updated_time=excluded.updated_time''',
    );
    try {
      for (final alias in aliases.toSet()) {
        if (alias.isEmpty) continue;
        statement.execute([alias, installationId, userId, updatedTime]);
      }
    } finally {
      statement.dispose();
    }
  });

  /// 根据持久化的物理 serial 或历史 route 查找最后一次 Companion 来源。
  Future<NotificationSource?> resolveSource(String alias) => _run((db) {
    final rows = db.select(
      '''SELECT installation, user_id FROM notification_sources
         WHERE alias = ? ORDER BY updated_time DESC LIMIT 1''',
      [alias],
    );
    if (rows.isEmpty) return null;
    return NotificationSource(
      installationId: rows.first['installation'] as String,
      androidUserId: rows.first['user_id'] as int,
    );
  });

  /// 启动时主动清理已超过 7 天的数据。
  Future<void> pruneExpired() => _run((db) {
    final sevenDaysAgo =
        DateTime.now().millisecondsSinceEpoch - (7 * 24 * 3600 * 1000);
    db.execute(
      'DELETE FROM notifications WHERE received_time < ?',
      [sevenDaysAgo],
    );
  });

  /// 清除指定设备别名或 serial 的所有通知记录及来源映射。
  Future<void> clearSource(String alias) => _run((db) {
    final rows = db.select(
      'SELECT installation, user_id FROM notification_sources WHERE alias = ?',
      [alias],
    );
    if (rows.isEmpty) return;
    final key = [rows.first['installation'], rows.first['user_id']];
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute(
        'DELETE FROM notifications WHERE installation=? AND user_id=?',
        key,
      );
      db.execute('DELETE FROM notification_sources WHERE alias=?', [alias]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  });
}
