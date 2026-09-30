import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/emulator/emulator_connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fake_adb_service.dart';

/// 模拟 console 和 host transport 命令，确保授权前不依赖 shell。
class _Adb extends FakeAdbService {
  final commands = <List<String>>[];
  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(args);
    return const AdbResult(
      exitCode: 0,
      stdout: 'Small_Phone\r\nOK\r\n',
      stderr: '',
    );
  }
}

void main() {
  test(
    'maps unauthorized and offline emulators without using shell on them',
    () async {
      for (final status in ['unauthorized', 'offline', 'device']) {
        final adb = _Adb();
        final result = await EmulatorConnectionService(adb).inspect([
          AdbDevice(id: 'emulator-5554', status: status),
          const AdbDevice(id: 'physical-device', status: 'device'),
        ]);
        expect(result['Small_Phone']!.status, status);
        expect(adb.commands, [
          ['-s', 'emulator-5554', 'emu', 'avd', 'name'],
        ]);
      }
    },
  );
  test('reconnect and stop target only the selected emulator', () async {
    final adb = _Adb();
    final service = EmulatorConnectionService(adb);
    await service.reconnect('emulator-5554');
    await service.stop('emulator-5554');
    expect(adb.commands, [
      ['-s', 'emulator-5554', 'reconnect'],
      ['-s', 'emulator-5554', 'emu', 'kill'],
    ]);
    expect(() => service.reconnect('physical-device'), throwsArgumentError);
  });
  test('invalid console output is not mistaken for an AVD name', () {
    expect(
      EmulatorConnectionService.parseAvdName('KO: emulator unavailable\n'),
      isNull,
    );
    expect(EmulatorConnectionService.parseAvdName('OK\n'), isNull);
  });
}
