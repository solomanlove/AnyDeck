import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:any_deck/core/cache/cache_cleanup_service.dart';

void main() {
  group('CacheCleanupService.cacheFolders', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp(
        'any_deck_cache_service_test_',
      );
    });

    tearDown(() async {
      if (sandbox.existsSync()) {
        await sandbox.delete(recursive: true);
      }
    });

    test('仅返回当前存在的缓存目录，并保留用途', () async {
      final home = Directory('${sandbox.path}/home');
      final systemTemp = Directory('${sandbox.path}/temp');
      await Directory(
        '${home.path}/Library/Caches/AnyDeck',
      ).create(recursive: true);
      await Directory('${systemTemp.path}/AnyDeck').create(recursive: true);

      final service = CacheCleanupService(
        homePath: home.path,
        systemTempPath: systemTemp.path,
      );

      final folders = service.cacheFolders(existingOnly: true);

      expect(folders.map((folder) => folder.kind), [
        CacheFolderKind.app,
        CacheFolderKind.temporary,
      ]);
      expect(
        folders.every((folder) => Directory(folder.path).existsSync()),
        isTrue,
      );
    });

    test('打开与清理共用的目录清单不会产生重复路径', () {
      final service = CacheCleanupService(
        homePath: '${sandbox.path}/home',
        systemTempPath: '${sandbox.path}/temp',
      );

      final folders = service.cacheFolders();
      final paths = folders.map((folder) => folder.path).toSet();

      expect(folders, hasLength(5));
      expect(paths, hasLength(folders.length));
    });
  });
}
