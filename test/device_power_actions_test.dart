import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/device_actions/device_action_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/dashboard/presentation/widgets/device_power_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _PowerAdbService extends AdbService {
  _PowerAdbService(this.result) : super(executable: 'adb');

  final AdbResult result;
  final List<List<String>> shellCommands = [];

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    shellCommands.add(args);
    return result;
  }
}

void main() {
  const deviceId = 'device-1';

  test(
    'pressPowerKeyAndResetScreenPower resets screen-off state on success',
    () async {
      final adb = _PowerAdbService(
        const AdbResult(exitCode: 0, stdout: '', stderr: ''),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(screenPowerOffProvider(deviceId).notifier).setOff(true);

      final result = await pressPowerKeyAndResetScreenPower(
        actions: DeviceActionService(adb),
        deviceId: deviceId,
        screenPowerOffNotifier: container.read(
          screenPowerOffProvider(deviceId).notifier,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(adb.shellCommands, [
        ['input', 'keyevent', 'KEYCODE_POWER'],
      ]);
      expect(container.read(screenPowerOffProvider(deviceId)), isFalse);
    },
  );

  test(
    'pressPowerKeyAndResetScreenPower keeps state when power key fails',
    () async {
      final adb = _PowerAdbService(
        const AdbResult(exitCode: 1, stdout: '', stderr: 'failed'),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(screenPowerOffProvider(deviceId).notifier).setOff(true);

      final result = await pressPowerKeyAndResetScreenPower(
        actions: DeviceActionService(adb),
        deviceId: deviceId,
        screenPowerOffNotifier: container.read(
          screenPowerOffProvider(deviceId).notifier,
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(container.read(screenPowerOffProvider(deviceId)), isTrue);
    },
  );
}
