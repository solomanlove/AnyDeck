import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:any_deck/core/notifications/notification_device_identity.dart';
import 'package:any_deck/core/notifications/notification_database.dart';
import 'package:any_deck/core/notifications/notification_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late NotificationDatabase database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notification_db_test_');
    dbPath = '${tempDir.path}/notifications.sqlite';
    database = NotificationDatabase(dbPath);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('inserts and queries notification items', () async {
    final now = DateTime.now();
    final item = NotificationMessage(
      installationId: 'inst_a',
      androidUserId: 0,
      notificationKey: 'notif_1',
      packageName: 'com.tencent.mm',
      appName: '微信',
      title: '张三',
      content: '今晚一起吃饭吗？',
      postTime: now,
      receivedTime: now,
    );

    final inserted = await database.insertOrUpdate(item);
    expect(inserted.id, isNotNull);

    final results = await database.queryMessages('inst_a', 0);
    expect(results.length, equals(1));
    expect(results.first.notificationKey, equals('notif_1'));
    expect(results.first.appName, equals('微信'));
    expect(results.first.content, equals('今晚一起吃饭吗？'));
    expect(results.first.isRemoved, isFalse);
  });

  test('filters by search term and package name', () async {
    final now = DateTime.now();
    final item1 = NotificationMessage(
      installationId: 'inst_1',
      androidUserId: 0,
      notificationKey: 'key_1',
      packageName: 'com.example.app1',
      appName: 'Alpha',
      title: 'Project Update',
      content: 'Release ready',
      postTime: now,
      receivedTime: now,
    );
    final item2 = NotificationMessage(
      installationId: 'inst_1',
      androidUserId: 0,
      notificationKey: 'key_2',
      packageName: 'com.example.app2',
      appName: 'Beta',
      title: 'Lunch',
      content: 'Pizza time',
      postTime: now,
      receivedTime: now.add(const Duration(seconds: 1)),
    );

    await database.insertOrUpdate(item1);
    await database.insertOrUpdate(item2);

    final searchAlpha = await database.queryMessages(
      'inst_1',
      0,
      query: 'update',
    );
    expect(searchAlpha.length, equals(1));
    expect(searchAlpha.first.notificationKey, equals('key_1'));

    final filterPackage = await database.queryMessages(
      'inst_1',
      0,
      packageName: 'com.example.app2',
    );
    expect(filterPackage.length, equals(1));
    expect(filterPackage.first.notificationKey, equals('key_2'));
  });

  test('marks notification as removed on phone', () async {
    final now = DateTime.now();
    final item = NotificationMessage(
      installationId: 'inst_rem',
      androidUserId: 0,
      notificationKey: 'to_remove',
      packageName: 'com.test',
      appName: 'Test',
      title: 'Notice',
      content: 'Going away',
      postTime: now,
      receivedTime: now,
    );

    await database.insertOrUpdate(item);
    await database.markAsRemoved('inst_rem', 0, 'to_remove');

    final results = await database.queryMessages('inst_rem', 0);
    expect(results.first.isRemoved, isTrue);
  });

  test('clears messages for specific device installation', () async {
    final now = DateTime.now();
    final itemA = NotificationMessage(
      installationId: 'inst_a',
      androidUserId: 0,
      notificationKey: 'k_a',
      packageName: 'com.a',
      appName: 'A',
      title: 'A',
      content: 'A',
      postTime: now,
      receivedTime: now,
    );
    final itemB = NotificationMessage(
      installationId: 'inst_b',
      androidUserId: 0,
      notificationKey: 'k_b',
      packageName: 'com.b',
      appName: 'B',
      title: 'B',
      content: 'B',
      postTime: now,
      receivedTime: now,
    );

    await database.insertOrUpdate(itemA);
    await database.insertOrUpdate(itemB);
    await database.clearMessages('inst_a', 0);

    expect((await database.queryMessages('inst_a', 0)).isEmpty, isTrue);
    expect((await database.queryMessages('inst_b', 0)).length, equals(1));
  });

  test('persists notification source aliases for offline history', () async {
    await database.linkSource(
      ['SERIAL_001', '192.168.1.8:5555'],
      'installation_a',
      10,
    );

    final serialSource = await database.resolveSource('SERIAL_001');
    final routeSource = await database.resolveSource('192.168.1.8:5555');

    expect(serialSource?.installationId, equals('installation_a'));
    expect(serialSource?.androidUserId, equals(10));
    expect(routeSource?.installationId, equals('installation_a'));
    expect(routeSource?.androidUserId, equals(10));
  });

  test('updates an alias when Companion is reinstalled', () async {
    await database.linkSource(['SERIAL_002'], 'installation_old', 0);
    await database.linkSource(['SERIAL_002'], 'installation_new', 11);

    final source = await database.resolveSource('SERIAL_002');
    expect(source?.installationId, equals('installation_new'));
    expect(source?.androidUserId, equals(11));
  });

  test('prunes messages older than 7 days', () async {
    final now = DateTime.now();
    final eightDaysAgo = now.subtract(const Duration(days: 8));
    final oneDayAgo = now.subtract(const Duration(days: 1));

    final oldItem = NotificationMessage(
      installationId: 'inst_age',
      androidUserId: 0,
      notificationKey: 'old_item',
      packageName: 'com.old',
      appName: 'Old',
      title: 'Old',
      content: 'Expired',
      postTime: eightDaysAgo,
      receivedTime: eightDaysAgo,
    );
    final recentItem = NotificationMessage(
      installationId: 'inst_age',
      androidUserId: 0,
      notificationKey: 'recent_item',
      packageName: 'com.new',
      appName: 'New',
      title: 'New',
      content: 'Fresh',
      postTime: oneDayAgo,
      receivedTime: oneDayAgo,
    );

    // 直接在同一 isolate 插入（绕过自动裁剪测试 pruneExpired 显式调用）
    await database.insertOrUpdate(recentItem);
    // 再次插入并将 oldItem 强制保存
    await database.insertOrUpdate(oldItem);
    await database.pruneExpired();

    final remaining = await database.queryMessages('inst_age', 0);
    expect(remaining.length, equals(1));
    expect(remaining.first.notificationKey, equals('recent_item'));
  });
  test('legacy database upgrades without losing source or messages', () async {
    final legacy = sqlite3.open(dbPath);
    legacy.execute(
      'CREATE TABLE notification_sources (alias TEXT PRIMARY KEY, installation TEXT NOT NULL, user_id INTEGER NOT NULL, updated_time INTEGER NOT NULL)',
    );
    legacy.execute(
      "INSERT INTO notification_sources VALUES ('USB', 'old', 0, 1)",
    );
    legacy.dispose();
    final source = await database.resolveSource('USB');
    expect(source?.installationId, 'old');
    expect(source?.identity, isNull);
    await database.linkSource(
      ['USB'],
      'old',
      0,
      identity: const NotificationDeviceIdentity(
        stableId: 'SERIAL',
        name: '旧手机',
      ),
    );
    expect((await database.resolveSource('USB'))?.identity?.name, '旧手机');
  });

  test('offline metadata survives reinstallation and route reuse', () async {
    await database.linkSource(
      ['SERIAL_A', '192.168.1.2:5555'],
      'old_a',
      0,
      identity: const NotificationDeviceIdentity(
        stableId: 'SERIAL_A',
        name: '工作手机',
      ),
    );
    await database.linkSource(
      ['SERIAL_A'],
      'new_a',
      0,
      identity: const NotificationDeviceIdentity(
        stableId: 'SERIAL_A',
        name: '工作手机新名',
      ),
    );
    await database.linkSource(
      ['SERIAL_B', '192.168.1.2:5555'],
      'b',
      10,
      identity: const NotificationDeviceIdentity(
        stableId: 'SERIAL_B',
        name: '私人手机',
      ),
    );
    final reopened = NotificationDatabase(dbPath);
    expect((await reopened.readSource('old_a', 0)).identity?.name, '工作手机');
    expect(
      (await reopened.resolveSource('SERIAL_A'))?.identity?.name,
      '工作手机新名',
    );
    expect(
      (await reopened.resolveSource('192.168.1.2:5555'))?.identity?.stableId,
      'SERIAL_B',
    );
    expect((await reopened.readSource('b', 0)).identity, isNull);
  });

  test(
    'target lookup never returns a message belonging to another source',
    () async {
      final now = DateTime.now();
      final saved = await database.insertOrUpdate(
        NotificationMessage(
          installationId: 'a',
          androidUserId: 0,
          notificationKey: 'same',
          packageName: 'chat',
          title: 'title',
          content: '',
          postTime: now,
          receivedTime: now,
        ),
      );
      expect(await database.queryMessageById('b', 0, saved.id!), isNull);
      expect(await database.queryMessageById('a', 10, saved.id!), isNull);
      expect(
        (await database.queryMessageById('a', 0, saved.id!))?.id,
        saved.id,
      );
    },
  );
}
