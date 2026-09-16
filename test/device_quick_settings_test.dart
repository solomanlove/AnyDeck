import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/device_actions/device_action_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockAdbService extends AdbService {
  _MockAdbService() : super(executable: 'adb');

  final List<List<String>> shellArgsCommands = [];

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    shellArgsCommands.add(args);
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  const deviceId = 'test-device-123';

  test('openQuickSettings runs statusbar expand-settings command', () async {
    final adb = _MockAdbService();
    final service = DeviceActionService(adb);

    final result = await service.openQuickSettings(deviceId);

    expect(result.isSuccess, isTrue);
    expect(adb.shellArgsCommands, [
      ['cmd', 'statusbar', 'expand-settings'],
    ]);
  });

  test('openNotificationBar runs statusbar expand-notifications command', () async {
    final adb = _MockAdbService();
    final service = DeviceActionService(adb);

    final result = await service.openNotificationBar(deviceId);

    expect(result.isSuccess, isTrue);
    expect(adb.shellArgsCommands, [
      ['cmd', 'statusbar', 'expand-notifications'],
    ]);
  });
}
