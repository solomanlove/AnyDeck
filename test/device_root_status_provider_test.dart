import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RootAdbService extends AdbService {
  _RootAdbService(this.results) : super(executable: 'unused');

  final Map<String, AdbResult> results;
  final List<String> commands = [];

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    expect(deviceId, 'target-device');
    commands.add(command);
    return results[command]!;
  }
}

void main() {
  const shellUser = AdbResult(
    exitCode: 0,
    stdout: 'uid=2000(shell) gid=2000(shell)',
    stderr: '',
  );
  const rootUser = AdbResult(
    exitCode: 0,
    stdout: 'uid=0(root) gid=0(root)',
    stderr: '',
  );
  const suPath = AdbResult(exitCode: 0, stdout: '/sbin/su', stderr: '');

  Future<(bool?, List<String>)> check(Map<String, AdbResult> results) async {
    final adb = _RootAdbService(results);
    final container = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(adb),
        deviceOnlineProvider('target-device').overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    final status = await container.read(
      deviceRootStatusProvider('target-device').future,
    );
    return (status, adb.commands);
  }

  test('ADB shell 已是 root 时直接确认', () async {
    final (status, commands) = await check({'id': rootUser});
    expect(status, isTrue);
    expect(commands, ['id']);
  });

  test('普通 shell 可通过 su 获取 root 时显示已 Root', () async {
    final (status, commands) = await check({
      'id': shellUser,
      'command -v su': suPath,
      'su -c id': rootUser,
    });
    expect(status, isTrue);
    expect(commands, ['id', 'command -v su', 'su -c id']);
  });

  test('找不到 su 时显示未 Root', () async {
    final (status, commands) = await check({
      'id': shellUser,
      'command -v su': const AdbResult(exitCode: 1, stdout: '', stderr: ''),
    });
    expect(status, isFalse);
    expect(commands, ['id', 'command -v su']);
  });

  test('su 授权被拒绝时状态未知', () async {
    final (status, commands) = await check({
      'id': shellUser,
      'command -v su': suPath,
      'su -c id': const AdbResult(
        exitCode: 1,
        stdout: '',
        stderr: 'permission denied',
      ),
    });
    expect(status, isNull);
    expect(commands, ['id', 'command -v su', 'su -c id']);
  });

  test('isDeviceRootProvider: 普通 shell 可通过 su 提权时为 true', () async {
    final adb = _RootAdbService({
      'id': shellUser,
      'command -v su': suPath,
      'su -c id': rootUser,
    });
    final container = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(adb),
        deviceOnlineProvider('target-device').overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    final isRoot = await container.read(
      isDeviceRootProvider('target-device').future,
    );
    expect(isRoot, isTrue);
  });

  test('isDeviceRootProvider: 无 su 提权能力时为 false', () async {
    final adb = _RootAdbService({
      'id': shellUser,
      'command -v su': const AdbResult(exitCode: 1, stdout: '', stderr: ''),
    });
    final container = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(adb),
        deviceOnlineProvider('target-device').overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    final isRoot = await container.read(
      isDeviceRootProvider('target-device').future,
    );
    expect(isRoot, isFalse);
  });
}
