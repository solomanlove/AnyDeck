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
    expect(result.message, '已断开');
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

  group('AdbService.sanitizePngBytes', () {
    const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    const iendChunk = [
      0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];

    test('returns original bytes when data is clean PNG', () {
      final cleanBytes = [...pngSignature, 1, 2, 3, ...iendChunk];
      final sanitized = AdbService.sanitizePngBytes(cleanBytes);
      expect(sanitized, equals(cleanBytes));
    });

    test('strips emulator warning prefix before PNG signature', () {
      const warningText =
          '[Warning] Multiple displays were found, but no display id was specified!\n'
          'See "dumpsys SurfaceFlinger --display-id" for valid display IDs.\n';
      final raw = [
        ...warningText.codeUnits,
        ...pngSignature,
        1,
        2,
        3,
        ...iendChunk,
      ];

      final logs = <String>[];
      final sanitized = AdbService.sanitizePngBytes(
        raw,
        onLog: (msg, {tag = '', level = ''}) => logs.add(msg),
      );

      expect(sanitized, equals([...pngSignature, 1, 2, 3, ...iendChunk]));
      expect(logs.any((l) => l.contains('warning/text prefix')), isTrue);
    });

    test('trims trailing junk data after IEND chunk', () {
      final raw = [
        ...pngSignature,
        1,
        2,
        3,
        ...iendChunk,
        ...'\n[Trailing noise]'.codeUnits,
      ];

      final logs = <String>[];
      final sanitized = AdbService.sanitizePngBytes(
        raw,
        onLog: (msg, {tag = '', level = ''}) => logs.add(msg),
      );

      expect(sanitized, equals([...pngSignature, 1, 2, 3, ...iendChunk]));
      expect(logs.any((l) => l.contains('trailing data')), isTrue);
    });

    test('throws AdbException when data is empty', () {
      expect(
        () => AdbService.sanitizePngBytes([]),
        throwsA(
          isA<AdbException>().having((e) => e.message, 'message', '未接收到截图数据'),
        ),
      );
    });

    test('throws AdbException with readable error when output is non-image text', () {
      const errorMsg = 'screencap: Permission denied';
      expect(
        () => AdbService.sanitizePngBytes(errorMsg.codeUnits),
        throwsA(
          isA<AdbException>().having((e) => e.message, 'message', errorMsg),
        ),
      );
    });
  });
}
