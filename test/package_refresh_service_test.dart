import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/apps/app_management_service.dart';
import 'package:any_deck/core/apps/package_refresh_progress.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_adb_service.dart';

/// 模拟真实分批包名文件和 helper 返回内容，不连接设备。
class _IconAdb extends FakeAdbService {
  final batches = <List<String>>[];
  int? failedPush;
  int? failedHelper;
  bool failSetup = false;
  bool omitLast = false;

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (args.contains('push') && args.last.contains('packages.txt.')) {
      batches.add(await File(args[3]).readAsLines());
      if (batches.length - 1 == failedPush) return _failure;
    } else if (failSetup) {
      return _failure;
    }
    return _success;
  }

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (command.contains('app_process')) {
      if (batches.length - 1 == failedHelper) return _failure;
      final names = omitLast
          ? batches.last.take(batches.last.length - 1)
          : batches.last;
      return AdbResult(
        exitCode: 0,
        stdout: names
            .map(
              (name) =>
                  '$name\t${base64Encode(utf8.encode('App $name'))}\t\tabcd',
            )
            .join('\n'),
        stderr: '',
      );
    }
    return _success;
  }
}

const _success = AdbResult(exitCode: 0, stdout: '', stderr: '');
const _failure = AdbResult(exitCode: 1, stdout: '', stderr: 'device offline');

List<AdbPackage> _packages(int count) => List.generate(
  count,
  (i) => AdbPackage(name: 'com.example.app$i', debuggable: true),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (_) async => ByteData(1));
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  test('真实批次进度包含尾批，元数据标识随增量结果保留', () async {
    final adb = _IconAdb();
    final progress = <PackageRefreshProgress>[];
    final updates = await AppManagementService(adb)
        .enrichPackagesWithIconsProgressive(
          'refresh_test',
          _packages(103),
          onProgress: progress.add,
          throwOnError: true,
        )
        .toList();
    expect(adb.batches.map((batch) => batch.length), [50, 50, 3]);
    expect(progress.map((p) => p.processed), [50, 100, 103]);
    expect(progress.map((p) => p.total), everyElement(103));
    expect(progress.map((p) => p.failed), everyElement(0));
    expect(updates.last.every((p) => p.debuggable && p.label != null), isTrue);
  });

  for (final failPush in [true, false]) {
    test('${failPush ? 'push' : 'helper'} 批次失败也推进计数，后续批次继续刷新', () async {
      final adb = _IconAdb();
      if (failPush) {
        adb.failedPush = 0;
      } else {
        adb.failedHelper = 0;
      }
      final progress = <PackageRefreshProgress>[];
      final updates = await AppManagementService(adb)
          .enrichPackagesWithIconsProgressive(
            'refresh_test',
            _packages(53),
            onProgress: progress.add,
            throwOnError: true,
          )
          .toList();
      expect(progress.map((p) => p.processed), [50, 53]);
      expect(progress.last.failed, 50);
      expect(updates.last.last.label, isNotNull);
      expect(updates.last.first.label, isNull);
    });
  }

  test('helper 缺失单个应用记录时报告部分失败', () async {
    final progress = <PackageRefreshProgress>[];
    await AppManagementService(_IconAdb()..omitLast = true)
        .enrichPackagesWithIconsProgressive(
          'refresh_test',
          _packages(3),
          onProgress: progress.add,
          throwOnError: true,
        )
        .drain<void>();
    expect(progress.single.processed, 3);
    expect(progress.single.failed, 1);
  });

  test('helper 初始化异常向手动刷新传播，后台默认调用保持容错', () async {
    final service = AppManagementService(_IconAdb()..failSetup = true);
    await expectLater(
      service
          .enrichPackagesWithIconsProgressive(
            'refresh_test',
            _packages(1),
            throwOnError: true,
          )
          .drain<void>(),
      throwsStateError,
    );
    await service
        .enrichPackagesWithIconsProgressive('refresh_test', _packages(1))
        .drain<void>();
  });

  test('空列表不执行 helper；释放后停止后续批次', () async {
    final adb = _IconAdb();
    final service = AppManagementService(adb);
    await service
        .enrichPackagesWithIconsProgressive('refresh_test', [])
        .drain<void>();
    expect(adb.batches, isEmpty);
    var active = true;
    await service
        .enrichPackagesWithIconsProgressive(
          'refresh_test',
          _packages(103),
          isActive: () => active,
          onProgress: (_) => active = false,
        )
        .drain<void>();
    expect(adb.batches, hasLength(1));
  });
}
