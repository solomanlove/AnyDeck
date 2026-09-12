import 'dart:convert';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/apps/app_management_service.dart';
import 'package:any_deck/core/usage/usage_snapshot.dart';
import 'package:any_deck/core/usage/usage_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/usage_fixture.dart';

String envelope(Map<String, dynamic> value) =>
    'Result: Bundle[{payload=${base64Encode(utf8.encode(jsonEncode(value)))}}]';

/// 模拟 current user 和 content call，检查不会退回 shell 特权统计或图标采集。
class UsageAdbFake extends AdbService {
  final commands = <List<String>>[];
  String response = envelope(usageFixture());
  bool installed = true;
  bool changesUser = false;
  int userReads = 0;

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(args);
    var output = '';
    if (args.join(' ') == 'am get-current-user') {
      output = changesUser && userReads++ > 0 ? '10' : '0';
    } else if (args.first == 'pm') {
      output = installed ? 'package:/data/app/companion/base.apk' : '';
    } else if (args.first == 'content') {
      output = response;
    } else {
      throw StateError('Unexpected ADB call');
    }
    return AdbResult(exitCode: 0, stdout: output, stderr: '');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('保留系统日桶边界，屏幕时长与重叠 App 累计分开', () {
    final report = UsageSnapshot.fromAdbOutput(envelope(usageFixture()));
    expect(report.rangeStartMs, lessThan(report.requestedStartMs));
    expect(report.screenInteractiveMs, 1800000);
    expect(report.combinedForegroundMs, 3000000);
    expect(report.apps.first.packageName, 'com.example.a');
  });

  test('缺少屏幕统计不等价于零，空 App 列表仍是有效快照', () {
    final json = usageFixture()
      ..remove('screenInteractiveMs')
      ..remove('screenRangeStartMs')
      ..remove('screenRangeEndMs');
    json['apps'] = [];
    final report = UsageSnapshot.fromJson(json);
    expect(report.screenInteractiveMs, isNull);
    expect(report.apps, isEmpty);
  });

  test('未知版本、负时长、重复包和破损响应均拒绝', () {
    final wrongVersion = usageFixture()..['schemaVersion'] = 2;
    final negative = usageFixture();
    negative['apps'][0]['foregroundMs'] = -1;
    final duplicates = usageFixture();
    duplicates['apps'].add(duplicates['apps'][0]);
    for (final json in [wrongVersion, negative, duplicates]) {
      expect(
        () => UsageSnapshot.fromAdbOutput(envelope(json)),
        throwsA(isA<UsageSyncException>()),
      );
    }
    expect(
      () => UsageSnapshot.fromAdbOutput('Error while accessing provider'),
      throwsA(isA<UsageSyncException>()),
    );
  });

  test('共享暂停、无权限和无数据返回可区分的状态', () {
    for (final entry in {
      'sharing_disabled': 'usageSharingDisabled',
      'permission_required': 'usagePermissionRequired',
      'no_data': 'usageNoData',
    }.entries) {
      expect(
        () => UsageSnapshot.fromAdbOutput(envelope({'status': entry.key})),
        throwsA(
          isA<UsageSyncException>().having(
            (error) => error.messageKey,
            'messageKey',
            entry.value,
          ),
        ),
      );
    }
  });

  test('只读取当前用户的 App 快照，不额外查询图标或直接 dumpsys usage', () async {
    final adb = UsageAdbFake();
    final report = await UsageSyncService(
      adb,
      AppManagementService(adb),
    ).sync('device');
    expect(report.androidUserId, 0);
    expect(adb.commands, hasLength(4));
    expect(adb.commands[2], containsAllInOrder(['--user', '0', '--uri']));
    expect(adb.commands.join(), isNot(contains('dumpsys')));
    expect(adb.commands.join(), isNot(contains('icon')));
  });

  test('当前用户缺少手机端时不执行统计读取', () async {
    final adb = UsageAdbFake()..installed = false;
    await expectLater(
      UsageSyncService(adb, AppManagementService(adb)).sync('device'),
      throwsA(
        isA<UsageSyncException>().having(
          (error) => error.messageKey,
          'messageKey',
          'usageCompanionMissing',
        ),
      ),
    );
    expect(adb.commands, hasLength(2));
  });

  test('同步途中切换 Android 用户时拒绝保存', () async {
    final adb = UsageAdbFake()..changesUser = true;
    await expectLater(
      UsageSyncService(adb, AppManagementService(adb)).sync('device'),
      throwsA(
        isA<UsageSyncException>().having(
          (error) => error.messageKey,
          'messageKey',
          'usageUserChanged',
        ),
      ),
    );
  });

  test('缓存重复保存是替换而非累计，设备之间隔离并支持清除', () async {
    final cache = UsageSnapshotCache();
    final report = UsageSnapshot.fromJson(usageFixture());
    await cache.save('deviceA', report);
    await cache.save('deviceA', report);
    expect((await cache.load('deviceA'))!.combinedForegroundMs, 3000000);
    expect(await cache.load('deviceB'), isNull);
    await cache.clear('deviceA');
    expect(await cache.load('deviceA'), isNull);
  });

  const deviceId = String.fromEnvironment('USAGE_ADB_DEVICE');
  test(
    '显式指定设备时验证手机 App → ADB → Dart → 快照缓存',
    () async {
      final adb = AdbService();
      final service = UsageSyncService(adb, AppManagementService(adb));
      final report = await service.sync(deviceId);
      expect(report.installationId, isNotEmpty);
      final cache = UsageSnapshotCache();
      await cache.save(deviceId, report);
      expect((await cache.load(deviceId))!.json, report.json);
      // 只输出统计数量；真实包名、时长和安装标识不写入测试日志或仓库。
      // ignore: avoid_print
      print('Live usage round trip passed: ${report.apps.length} app records.');
    },
    skip: deviceId.isEmpty,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
