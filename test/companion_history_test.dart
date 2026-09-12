import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/apps/app_management_service.dart';
import 'package:any_deck/core/usage/companion_database.dart';
import 'package:any_deck/core/usage/companion_history.dart';
import 'package:any_deck/core/usage/usage_snapshot.dart';
import 'package:any_deck/core/usage/usage_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/usage_fixture.dart';

/// 固定测试坐标只用于解析/入库验证，不能当成真机定位证据。
Map<String, dynamic> locationFixture() => {
  'latitude': 31.2,
  'longitude': 121.5,
  'accuracyMeters': 35.0,
  'capturedAtMs': 1789145000000,
  'receivedAtMs': 1789145001000,
  'provider': 'gps',
  'mock': false,
  'coordinateSystem': 'WGS84',
};

Map<String, dynamic> historyPage({
  String kind = 'location',
  int after = 0,
  int next = 1,
  int? upper,
  int first = 1,
  String installation = 'test-installation',
  int user = 0,
  List<Map<String, dynamic>>? records,
}) => {
  'status': 'ok',
  'schemaVersion': 2,
  'kind': kind,
  'installationId': installation,
  'androidUserId': user,
  'after': after,
  'nextCursor': next,
  'upperBound': upper ?? next,
  'firstAvailableId': first,
  'hasMore': next < (upper ?? next),
  'records':
      records ??
      [
        {
          'id': next,
          'recordedAtMs': 1789145001000,
          'data': kind == 'usage' ? usageFixture() : locationFixture(),
        },
      ],
};

String _envelope(Map<String, dynamic> json) =>
    'Result: Bundle[{payload=${base64Encode(utf8.encode(jsonEncode(json)))}}]';

class HistoryAdbFake extends AdbService {
  bool failSecond = true;
  final requestedCursors = <String>[];
  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (args.first == 'am') {
      return const AdbResult(exitCode: 0, stdout: '0', stderr: '');
    }
    final method = args[args.indexOf('--method') + 1];
    Map<String, dynamic> data;
    if (method == 'identity') {
      data = {
        'status': 'ok',
        'schemaVersion': 2,
        'installationId': 'test-installation',
        'androidUserId': 0,
      };
    } else {
      final cursor = args[args.indexOf('--arg') + 1];
      requestedCursors.add(cursor);
      final after = int.parse(cursor.split(':').first);
      if (after == 1 && failSecond) {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: 'device offline',
        );
      }
      data = after == 0
          ? historyPage(upper: 2)
          : historyPage(after: 1, next: 2);
    }
    return AdbResult(exitCode: 0, stdout: _envelope(data), stderr: '');
  }
}

void main() {
  late Directory directory;
  late CompanionDatabase database;
  const source = CompanionSource('test-installation', 0);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('companion_test_');
    database = CompanionDatabase('${directory.path}/history.sqlite');
  });
  tearDown(() async => directory.delete(recursive: true));

  test('真实 SQLite 文件重开仍有记录，重复页不重复入库，路由变更共用游标', () async {
    final page = CompanionPage.fromJson(historyPage());
    await database.importPage('usb', page);
    await database.importPage('wifi', page);
    final reopened = CompanionDatabase(database.path);
    expect((await reopened.load('wifi')).locations, hasLength(1));
    expect(await reopened.cursor(source, 'location'), 1);
    expect((await reopened.load('usb')).locations.single.latitude, 31.2);
  });

  test('记录插入和游标提交必须原子化，游标写入失败回滚整页', () async {
    await database.importPage('usb', CompanionPage.fromJson(historyPage()));
    final native = sqlite3.open(database.path);
    native.execute('''CREATE TRIGGER fail_cursor BEFORE UPDATE ON cursors
      BEGIN SELECT RAISE(ABORT, 'test write failure'); END''');
    native.dispose();
    await expectLater(
      database.importPage(
        'usb',
        CompanionPage.fromJson(historyPage(after: 1, next: 2)),
      ),
      throwsA(anything),
    );
    expect(await database.cursor(source, 'location'), 1);
    expect((await database.load('usb')).locations, hasLength(1));
  });

  test('新安装实例和 Android 用户独立，不能覆盖旧来源记录', () async {
    await database.importPage('old', CompanionPage.fromJson(historyPage()));
    await database.importPage(
      'other',
      CompanionPage.fromJson(historyPage(installation: 'second', user: 10)),
    );
    expect(
      (await database.load('old')).source!.installationId,
      'test-installation',
    );
    expect((await database.load('other')).source!.androidUserId, 10);
    await database.clear('other');
    expect((await database.load('old')).locations, hasLength(1));
    expect((await database.load('other')).locations, isEmpty);
  });

  test('旧版真实快照迁移不推进游标，同日使用统计只选择最后一份而非累加', () async {
    await database.migrateLegacy('usb', UsageSnapshot.fromJson(usageFixture()));
    expect(await database.cursor(source, 'usage'), 0);
    await database.importPage(
      'usb',
      CompanionPage.fromJson(historyPage(kind: 'usage')),
    );
    await database.importPage(
      'usb',
      CompanionPage.fromJson(historyPage(kind: 'usage', after: 1, next: 2)),
    );
    final report = await database.load('usb');
    expect(report.usage, hasLength(1));
    expect(report.usage.single.combinedForegroundMs, 3000000);
  });

  test('保留期导致的缺口需显式展示', () async {
    await database.importPage(
      'usb',
      CompanionPage.fromJson(historyPage(first: 5, next: 5)),
    );
    expect((await database.load('usb')).hasGap, isTrue);
  });

  test('中途断线保留已提交页，下次从游标恢复', () async {
    final adb = HistoryAdbFake();
    final service = UsageSyncService(adb, AppManagementService(adb));
    await expectLater(
      service.syncHistory('usb', 'stable', 'location', database),
      throwsA(isA<UsageSyncException>()),
    );
    expect(await database.cursor(source, 'location'), 1);
    adb.failSecond = false;
    await service.syncHistory('usb', 'stable', 'location', database);
    expect(adb.requestedCursors, ['0:0', '1:2', '1:0']);
    expect((await database.load('stable')).locations, hasLength(2));
  });

  test('无效坐标、身份串读、逆序记录和不前进的分页响应均拒绝', () {
    final invalid = historyPage();
    invalid['records'][0]['data']['latitude'] = 100;
    final wrongSource = historyPage(kind: 'usage', installation: 'other');
    final reversed = historyPage(after: 5, next: 4);
    final stalled = historyPage(after: 1, next: 1, upper: 2, records: []);
    for (final page in [invalid, wrongSource, reversed, stalled]) {
      expect(
        () => CompanionPage.fromJson(page),
        throwsA(isA<UsageSyncException>()),
      );
    }
  });

  const device = String.fromEnvironment('USAGE_ADB_DEVICE');
  const requireLocation = bool.fromEnvironment('REQUIRE_REAL_LOCATION');
  test(
    '真机真实历史 → ADB → 实体 SQLite 文件 → 重开回读',
    () async {
      final adb = AdbService();
      final service = UsageSyncService(adb, AppManagementService(adb));
      await service.syncHistory(device, 'live', 'usage', database);
      if (requireLocation) {
        await service.syncHistory(device, 'live', 'location', database);
      }
      final view = await CompanionDatabase(database.path).load('live');
      expect(view.usage, isNotEmpty);
      if (requireLocation) {
        expect(view.locations.where((point) => !point.mock), isNotEmpty);
      }
      // 不把真实坐标、包名和使用时间输出到测试日志。
    },
    skip: device.isEmpty,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
