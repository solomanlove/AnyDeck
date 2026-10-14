import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/device_actions/device_action_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 按调用顺序返回音量命令结果，用于模拟 ROM 返回成功但实际未生效。
class _VolumeAdbService extends AdbService {
  _VolumeAdbService(this.results) : super(executable: 'adb');

  final List<AdbResult> results;
  final List<List<String>> commands = [];

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(args);
    if (results.isEmpty) {
      return const AdbResult(exitCode: 0, stdout: '', stderr: '');
    }
    return results.removeAt(0);
  }
}

const _success = AdbResult(exitCode: 0, stdout: '', stderr: '');

AdbResult _volumeState(int current, int max) => AdbResult(
  exitCode: 0,
  stdout: '[V] volume is $current in range [0..$max]',
  stderr: '',
);

void main() {
  test('音量命令返回成功但回读未到最大值时使用批量按键兜底', () async {
    final adb = _VolumeAdbService([
      _success,
      _volumeState(9, 25),
      _success,
      _volumeState(9, 25),
      _success,
    ]);
    final service = DeviceActionService(adb, sdkVersionResolver: (_) => 35);

    final result = await service.volumeMax('phone');

    expect(result.isSuccess, isTrue);
    expect(adb.commands.last, [
      'input',
      'keyevent',
      ...List.filled(30, 'KEYCODE_VOLUME_UP'),
    ]);
  });

  test('回读已经达到最大值时不重复注入音量按键', () async {
    final adb = _VolumeAdbService([
      _success,
      _volumeState(9, 25),
      _success,
      _volumeState(25, 25),
    ]);
    final service = DeviceActionService(adb, sdkVersionResolver: (_) => 35);

    final result = await service.volumeMax('phone');

    expect(result.isSuccess, isTrue);
    expect(
      adb.commands.where((command) => command.contains('KEYCODE_VOLUME_UP')),
      isEmpty,
    );
  });
}
