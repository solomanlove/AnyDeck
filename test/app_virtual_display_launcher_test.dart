import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/scrcpy/app_virtual_display_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟厂商 ROM：包名 Intent 无法启动，明确的 LAUNCHER Component 可以启动。
class _LauncherAdbFake extends AdbService {
  _LauncherAdbFake() : super(executable: 'adb');

  final commands = <List<String>>[];
  String resolvedActivity =
      'priority=0 preferredOrder=0 match=0x108000\n'
      'cn.yibu.yibu_app/.MainActivity\n';

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(args);
    if (args.contains('resolve-activity')) {
      return AdbResult(exitCode: 0, stdout: resolvedActivity, stderr: '');
    }
    if (args.contains('stack') && args.contains('list')) {
      return const AdbResult(exitCode: 0, stdout: '', stderr: '');
    }
    if (args.contains('start')) {
      return args.contains('-n')
          ? const AdbResult(exitCode: 0, stdout: 'Status: ok', stderr: '')
          : const AdbResult(
              exitCode: 1,
              stdout: 'Error: Activity not started, unable to resolve Intent',
              stderr: '',
            );
    }
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  test('虚拟副屏用解析出的 Activity 显式启动', () async {
    final adb = _LauncherAdbFake();
    final guardian = await launchAppOnVirtualDisplay(
      adbService: adb,
      deviceId: 'phone',
      packageName: 'cn.yibu.yibu_app',
      displayIdFuture: Future.value(113),
    );
    guardian.cancel();

    final resolve = adb.commands.singleWhere(
      (args) => args.contains('resolve-activity'),
    );
    expect(
      resolve,
      containsAllInOrder(['--user', 'current', '-p', 'cn.yibu.yibu_app']),
    );
    final start = adb.commands.singleWhere((args) => args.contains('start'));
    expect(
      start,
      containsAllInOrder([
        '-n',
        'cn.yibu.yibu_app/.MainActivity',
        '--display',
        '113',
      ]),
    );
    expect(start, isNot(contains('-p')));
  });

  test('关闭融合后主屏也使用显式 Activity', () async {
    final adb = _LauncherAdbFake();
    await launchAppOnPrimaryDisplay(
      adbService: adb,
      deviceId: 'phone',
      packageName: 'cn.yibu.yibu_app',
    );

    final start = adb.commands.singleWhere((args) => args.contains('start'));
    expect(
      start,
      containsAllInOrder([
        '-n',
        'cn.yibu.yibu_app/.MainActivity',
        '--display',
        '0',
      ]),
    );
  });

  test('未安装或没有 LAUNCHER Activity 时不尝试启动', () async {
    final adb = _LauncherAdbFake()..resolvedActivity = 'No activity found\n';
    await expectLater(
      launchAppOnVirtualDisplay(
        adbService: adb,
        deviceId: 'phone',
        packageName: 'cn.yibu.yibu_app',
        displayIdFuture: Future.value(113),
      ),
      throwsA(isA<StateError>()),
    );
    expect(adb.commands.where((args) => args.contains('start')), isEmpty);
  });
}
