import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// 展示元数据的磁盘索引；JSON、SQLite 与图标文件检查全部在 worker 中执行。
class PackageMetadataIndex {
  const PackageMetadataIndex(this.path, this.iconRoot);
  final String path;
  final String iconRoot;

  static Future<PackageMetadataIndex> openDefault() async {
    final directory = await getApplicationSupportDirectory();
    final userDirectory = Platform.environment['HOME'];
    final root = userDirectory == null
        ? '${Directory.systemTemp.path}/AnyDeck/package_icons'
        : '$userDirectory/Library/Caches/AnyDeck/package_icons';
    return PackageMetadataIndex('${directory.path}/apps/metadata.sqlite', root);
  }

  Future<T> _run<T>(T Function(Database) action) {
    final databasePath = path;
    return Isolate.run(() {
      File(databasePath).parent.createSync(recursive: true);
      final db = sqlite3.open(databasePath);
      try {
        db.execute('PRAGMA busy_timeout=5000');
        db.execute('PRAGMA journal_mode=WAL');
        db.execute('''CREATE TABLE IF NOT EXISTS metadata (
          source TEXT NOT NULL, package TEXT NOT NULL, label TEXT, icon TEXT,
          saved_at INTEGER NOT NULL, PRIMARY KEY(source, package))''');
        db.execute(
          'CREATE INDEX IF NOT EXISTS metadata_package ON metadata(package)',
        );
        db.execute(
          'CREATE TABLE IF NOT EXISTS imports (source TEXT PRIMARY KEY, fingerprint TEXT NOT NULL)',
        );
        return action(db);
      } finally {
        db.dispose();
      }
    });
  }

  /// 每次只迁移一个旧快照，指纹不变时跳过解码；不向 UI 返回整份包列表。
  Future<void> importLegacy(String source, String raw) => _run((db) {
    final fingerprint = sha256.convert(utf8.encode(raw)).toString();
    if (db.select('SELECT 1 FROM imports WHERE source=? AND fingerprint=?', [
      source,
      fingerprint,
    ]).isNotEmpty) {
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['items'] is! List) return;
    final savedAt =
        DateTime.tryParse('${decoded['savedAt']}')?.millisecondsSinceEpoch ?? 0;
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute('DELETE FROM metadata WHERE source=?', [source]);
      final insert = db.prepare(
        'INSERT OR REPLACE INTO metadata VALUES (?,?,?,?,?)',
      );
      try {
        for (final item in decoded['items'] as List) {
          if (item is! Map) continue;
          final name = item['name'];
          if (name is! String || name.isEmpty || name.length > 512) continue;
          final label = item['label'] as String?;
          final icon = item['iconLocalPath'] as String?;
          insert.execute([
            source,
            name,
            label?.substring(0, label.length.clamp(0, 1024)),
            icon != null && icon.length <= 4096 ? icon : null,
            savedAt,
          ]);
        }
      } finally {
        insert.dispose();
      }
      db.execute('INSERT OR REPLACE INTO imports VALUES (?,?)', [
        source,
        fingerprint,
      ]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  });

  /// 被用户删除的旧快照不再留在历史展示索引中。
  Future<void> retainSources(Set<String> sources) => _run((db) {
    for (final row in db.select('SELECT source FROM imports')) {
      if (sources.contains(row['source'])) continue;
      db.execute('DELETE FROM metadata WHERE source=?', [row['source']]);
      db.execute('DELETE FROM imports WHERE source=?', [row['source']]);
    }
  });

  /// 每批最多处理可见页面请求的 128 项，图标缺失时只探测确定文件名。
  Future<Map<String, Map<String, String>>> lookup(
    Map<String, (String, String?)> requests,
  ) {
    final root = iconRoot;
    return _run((db) {
      final result = <String, Map<String, String>>{};
      List<Directory>? directories;
      for (final request in requests.entries.take(128)) {
        final (name, preferred) = request.value;
        final rows = db.select(
          '''SELECT label,icon FROM metadata WHERE package=?
          ORDER BY source IN (?,?) DESC, saved_at DESC LIMIT 32''',
          [name, 'apps.packages.v4.$preferred', 'apps.packages.v3.$preferred'],
        );
        String? label, icon;
        for (final row in rows) {
          label ??= row['label'] as String?;
          final candidate = row['icon'] as String?;
          if (candidate != null && File(candidate).existsSync()) {
            icon ??= candidate;
          }
        }
        if (icon == null && RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(name)) {
          final directory = Directory(root);
          if (directory.existsSync()) {
            directories ??= directory
                .listSync(followLinks: false)
                .whereType<Directory>()
                .toList();
            final safeId = preferred?.replaceAll(
              RegExp(r'[^A-Za-z0-9._-]'),
              '_',
            );
            final ordered = [
              ...directories.where(
                (dir) =>
                    dir.uri.pathSegments.where((s) => s.isNotEmpty).last ==
                    safeId,
              ),
              ...directories.where(
                (dir) =>
                    dir.uri.pathSegments.where((s) => s.isNotEmpty).last !=
                    safeId,
              ),
            ];
            for (final dir in ordered) {
              for (final extension in ['png', 'webp', 'jpg', 'jpeg']) {
                final file = File('${dir.path}/$name.$extension');
                if (file.existsSync() && file.lengthSync() > 0) {
                  icon = file.path;
                  break;
                }
              }
              if (icon != null) break;
            }
          }
        }
        result[request.key] = {'label': ?label, 'icon': ?icon};
      }
      return result;
    });
  }
}
