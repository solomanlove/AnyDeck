import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/apps/app_management_service.dart';
import 'package:any_deck/core/apps/package_metadata_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _snapshot(String label, String? icon) => jsonEncode({
  'savedAt': '2026-11-07T00:00:00Z',
  'items': [
    {'name': 'com.example.app', 'label': label, 'iconLocalPath': icon},
  ],
});

/// 在临时 SQLite/图标目录验证历史兼容、按需读取和缓存上限。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PackageMetadataIndex index;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('anydeck_metadata_test_');
    index = PackageMetadataIndex(
      '${directory.path}/metadata.sqlite',
      '${directory.path}/icons',
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('优先当前设备名称，坏图标回退有效历史图标；更新及删除源快照同步索引', () async {
    final icon = File('${directory.path}/valid.png')
      ..writeAsStringSync('fixture');
    await index.importLegacy('apps.packages.v4.a', _snapshot('A', icon.path));
    await index.importLegacy(
      'apps.packages.v4.b',
      _snapshot('B', '${directory.path}/missing.png'),
    );
    const requests = {'row': ('com.example.app', 'b')};
    expect((await index.lookup(requests))['row'], {
      'label': 'B',
      'icon': icon.path,
    });
    await index.importLegacy('apps.packages.v4.b', _snapshot('B2', null));
    expect((await index.lookup(requests))['row']!['label'], 'B2');
    await index.retainSources({'apps.packages.v4.a'});
    expect((await index.lookup(requests))['row']!['label'], 'A');
  });

  test('图标扫描在 worker 按确定文件名查找，支持指定设备优先', () async {
    final a = File('${directory.path}/icons/a/com.example.app.png');
    final b = File('${directory.path}/icons/b/com.example.app.webp');
    a.parent.createSync(recursive: true);
    b.parent.createSync(recursive: true);
    a.writeAsStringSync('a');
    b.writeAsStringSync('b');
    final result = await index.lookup({'row': ('com.example.app', 'b')});
    expect(result['row']!['icon'], b.path);
  });

  test('LRU 及待查询队列有界，热路径无需访问磁盘', () {
    final resolver = PackageMetadataResolver(
      AppManagementService(AdbService()),
      index: index,
      maxEntries: 3,
    );
    addTearDown(resolver.dispose);
    for (var i = 0; i < 10; i++) {
      resolver.resolve(
        AdbPackage(name: 'app.$i', label: '$i', iconLocalPath: '/missing/$i'),
      );
    }
    expect(resolver.cachedEntries, 3);
    for (var i = 0; i < 1000; i++) {
      resolver.findIconOnDisk('uncached.$i');
    }
    expect(resolver.pendingEntries, 128);
  });

  test('坏图标回报后可显式清除旧路径，避免错误回调反复触发查询', () {
    final resolver = PackageMetadataResolver(
      AppManagementService(AdbService()),
      index: index,
    );
    addTearDown(resolver.dispose);
    const package = AdbPackage(
      name: 'com.example.app',
      label: 'Example',
      iconLocalPath: '/missing/icon.png',
    );
    resolver.resolve(package);
    resolver.reportMissingIcon(package.name, package.iconLocalPath!);
    expect(resolver.resolve(package).iconLocalPath, isNull);
    expect(resolver.findIconOnDisk(package.name), isNull);
  });

  test('历史快照按需迁移，只把请求项放进 UI 缓存；负缓存防止重复查询', () async {
    SharedPreferences.setMockInitialValues({
      'apps.packages.v4.old': jsonEncode({
        'items': [
          for (var i = 0; i < 2000; i++) {'name': 'app.$i', 'label': '历史 $i'},
        ],
      }),
      'apps.packages.v3.broken': 'broken json',
    });
    final completed = Completer<void>();
    var updates = 0;
    final resolver = PackageMetadataResolver(
      AppManagementService(AdbService()),
      index: index,
      maxEntries: 4,
      onCacheUpdated: () {
        updates++;
        if (!completed.isCompleted) completed.complete();
      },
    );
    addTearDown(resolver.dispose);
    await resolver.warmup();
    expect(resolver.cachedEntries, 0);
    resolver.resolve(const AdbPackage(name: 'app.1999'));
    await completed.future.timeout(const Duration(seconds: 10));
    expect(
      resolver.resolve(const AdbPackage(name: 'app.1999')).label,
      '历史 1999',
    );
    expect(resolver.cachedEntries, 1);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(updates, 1);
  });
}
