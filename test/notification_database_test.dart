import 'dart:io';
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
}
