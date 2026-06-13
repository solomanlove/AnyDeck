import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAdbService extends AdbService {
  FakeAdbService(this.output) : super(executable: 'adb');

  final String output;

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return AdbResult(exitCode: 0, stdout: output, stderr: '');
  }
}

void main() {
  test('maps adb device not found errors to disconnected message', () {
    const result = AdbResult(
      exitCode: 1,
      stdout: '',
      stderr:
          "adb: device 'adb-5002ba00-9wYbHj._adb-tls-connect._tcp' not found",
    );

    expect(result.isDeviceDisconnected, isTrue);
    expect(
      result.disconnectedDeviceId,
      'adb-5002ba00-9wYbHj._adb-tls-connect._tcp',
    );
    expect(result.message, 'adb已断开');
  });

  test('parses mdns device ids containing spaces', () async {
    const output = '''
List of devices attached
adb-5002ba00-9wYbHj._adb-tls-connect._tcp device product:alioth model:M2012K11AC device:alioth transport_id:16
adb-6618d198-XEvEat (2)._adb-tls-connect._tcp device product:pudding model:25113PN0EC device:pudding transport_id:13
''';

    final devices = await FakeAdbService(output).listDevices();

    expect(devices, hasLength(2));
    expect(devices[0].id, 'adb-5002ba00-9wYbHj._adb-tls-connect._tcp');
    expect(devices[0].status, 'device');
    expect(devices[0].model, 'M2012K11AC');
    expect(devices[1].id, 'adb-6618d198-XEvEat (2)._adb-tls-connect._tcp');
    expect(devices[1].status, 'device');
    expect(devices[1].model, '25113PN0EC');
  });
}
