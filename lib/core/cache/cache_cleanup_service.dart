import 'dart:io';

/// 清理 AnyDeck 自有缓存目录，不触碰 SharedPreferences 和用户选择的保存路径。
class CacheCleanupService {
  CacheCleanupService({String? homePath, String? systemTempPath})
    : _homePath = homePath ?? Platform.environment['HOME'],
      _systemTempPath = systemTempPath ?? Directory.systemTemp.path;

  final String? _homePath;
  final String _systemTempPath;

  /// 返回 AnyDeck 维护的缓存目录，打开和清理操作共用同一份路径清单。
  List<CacheFolderLocation> cacheFolders({bool existingOnly = false}) {
    final home = _homePath;
    final folders = <CacheFolderLocation>[
      if (home != null && home.isNotEmpty)
        CacheFolderLocation(
          kind: CacheFolderKind.app,
          path: '$home/Library/Caches/AnyDeck',
        ),
      CacheFolderLocation(
        kind: CacheFolderKind.temporary,
        path: '$_systemTempPath/AnyDeck',
      ),
      CacheFolderLocation(
        kind: CacheFolderKind.packages,
        path: '$_systemTempPath/any_deck_packages',
      ),
      CacheFolderLocation(
        kind: CacheFolderKind.helper,
        path: '$_systemTempPath/any_deck_helper',
      ),
      CacheFolderLocation(
        kind: CacheFolderKind.scrcpy,
        path: '$_systemTempPath/any_deck_scrcpy',
      ),
    ];

    // 路径可能因宿主机配置重合，按绝对路径去重并保留首个用途说明。
    final uniqueFolders = <String, CacheFolderLocation>{};
    for (final folder in folders) {
      uniqueFolders.putIfAbsent(folder.path, () => folder);
    }
    final result = uniqueFolders.values;
    return (existingOnly
            ? result.where((folder) => Directory(folder.path).existsSync())
            : result)
        .toList(growable: false);
  }

  Future<CacheCleanupResult> clearCacheFolders() async {
    final targets = cacheFolders()
        .map((folder) => Directory(folder.path))
        .toList(growable: false);
    var deletedFolders = 0;
    var deletedFiles = 0;
    var freedBytes = 0;

    for (final target in targets) {
      if (!target.existsSync()) {
        continue;
      }
      final stats = await _measure(target);
      freedBytes += stats.bytes;
      deletedFiles += stats.files;
      deletedFolders += stats.directories;
      await target.delete(recursive: true);
    }

    return CacheCleanupResult(
      deletedFolders: deletedFolders,
      deletedFiles: deletedFiles,
      freedBytes: freedBytes,
    );
  }

  Future<_CacheStats> _measure(FileSystemEntity entity) async {
    if (entity is File) {
      return _CacheStats(
        files: 1,
        directories: 0,
        bytes: await entity.length(),
      );
    }
    if (entity is! Directory) {
      return const _CacheStats(files: 0, directories: 0, bytes: 0);
    }

    var files = 0;
    var directories = 1;
    var bytes = 0;
    await for (final child in entity.list(
      recursive: true,
      followLinks: false,
    )) {
      if (child is File) {
        files += 1;
        bytes += await child.length();
      } else if (child is Directory) {
        directories += 1;
      }
    }
    return _CacheStats(files: files, directories: directories, bytes: bytes);
  }
}

/// 缓存目录用途，用于由 UI 提供 localized 名称。
enum CacheFolderKind { app, temporary, packages, helper, scrcpy }

/// 缓存目录位置，路径本身由 [CacheCleanupService] 统一维护。
class CacheFolderLocation {
  const CacheFolderLocation({required this.kind, required this.path});

  final CacheFolderKind kind;
  final String path;
}

class CacheCleanupResult {
  const CacheCleanupResult({
    required this.deletedFolders,
    required this.deletedFiles,
    required this.freedBytes,
  });

  final int deletedFolders;
  final int deletedFiles;
  final int freedBytes;
}

class _CacheStats {
  const _CacheStats({
    required this.files,
    required this.directories,
    required this.bytes,
  });

  final int files;
  final int directories;
  final int bytes;
}
