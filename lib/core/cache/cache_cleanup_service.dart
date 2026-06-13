import 'dart:io';

/// 清理 AnyDeck 自有缓存目录，不触碰 SharedPreferences 和用户选择的保存路径。
class CacheCleanupService {
  Future<CacheCleanupResult> clearCacheFolders() async {
    final targets = _cacheTargets();
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
      if (target is Directory) {
        deletedFolders += stats.directories;
      }
      await target.delete(recursive: true);
    }

    return CacheCleanupResult(
      deletedFolders: deletedFolders,
      deletedFiles: deletedFiles,
      freedBytes: freedBytes,
    );
  }

  List<FileSystemEntity> _cacheTargets() {
    final home = Platform.environment['HOME'];
    final targets = <String>{
      if (home != null && home.isNotEmpty) '$home/Library/Caches/AnyDeck',
      '${Directory.systemTemp.path}/AnyDeck',
      '${Directory.systemTemp.path}/any_deck_packages',
      '${Directory.systemTemp.path}/any_deck_helper',
      '${Directory.systemTemp.path}/any_deck_scrcpy',
    };
    return targets.map(Directory.new).toList(growable: false);
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
