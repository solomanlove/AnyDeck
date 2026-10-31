import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/providers/modules/device_tracking_providers.dart';
import 'package:any_deck/core/providers/modules/harmony_wireless_connection_provider.dart';
import 'package:any_deck/core/providers/modules/service_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IdentityHdc extends HdcService {
  _IdentityHdc(this.serial) : super(executable: 'hdc');

  final String? serial;
  final List<List<String>> commands = [];

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(args);
    return const AdbResult(exitCode: 0, stdout: 'Connect OK', stderr: '');
  }

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (serial == null) {
      return const AdbResult(exitCode: 1, stdout: '', stderr: 'unavailable');
    }
    return AdbResult(exitCode: 0, stdout: serial!, stderr: '');
  }
}

ProviderContainer _container(HdcService hdc) {
  return ProviderContainer(
    overrides: [
      hdcServiceProvider.overrideWithValue(hdc),
      discoveredDevicesProvider.overrideWith((ref) => Stream.value(const [])),
    ],
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'successful manual connection persists the verified device identity',
    () async {
      final hdc = _IdentityHdc('DEVICE-SERIAL-001');
      final container = _container(hdc);
      addTearDown(container.dispose);

      final result = await container
          .read(harmonyWirelessConnectionProvider.notifier)
          .connect('192.168.1.8:5555');

      expect(result.isSuccess, isTrue);
      final endpoint = container.read(harmonyWirelessConnectionProvider).history.single;
      expect(endpoint.address, '192.168.1.8:5555');
      expect(endpoint.deviceSerial, 'DEVICE-SERIAL-001');
    },
  );

  test(
    'identity mismatch disconnects the address and does not save history',
    () async {
      final hdc = _IdentityHdc('OTHER-DEVICE');
      final container = _container(hdc);
      addTearDown(container.dispose);

      final result = await container
          .read(harmonyWirelessConnectionProvider.notifier)
          .connect('192.168.1.9:5555', expectedSerial: 'EXPECTED-DEVICE');

      expect(result.isSuccess, isFalse);
      expect(container.read(harmonyWirelessConnectionProvider).history, isEmpty);
      expect(
        hdc.commands,
        contains(equals(['tconn', '192.168.1.9:5555', '-remove'])),
      );
    },
  );

  test(
    'unverifiable identity is rejected instead of becoming reconnect history',
    () async {
      final hdc = _IdentityHdc(null);
      final container = _container(hdc);
      addTearDown(container.dispose);

      final result = await container
          .read(harmonyWirelessConnectionProvider.notifier)
          .connect('192.168.1.10:5555');

      expect(result.isSuccess, isFalse);
      expect(container.read(harmonyWirelessConnectionProvider).history, isEmpty);
    },
  );
}
