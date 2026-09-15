import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IosDeviceService Tests', () {
    test('parseDeviceListOutput correctly parses JSON output with warning lines and deduplicates', () {
      const rawOutput = '''
{"time":"2026-09-15T09:56:31.896207+08:00","level":"WARN","msg":"go-ios agent is not running. You might need to start it with 'ios tunnel start'"}
{"deviceList":[{"Udid":"c2b1632e9949e742d81c5d4ef11d356bd4687014","ProductName":"iPhone OS","ProductType":"iPhone8,1","ProductVersion":"15.8.8","ConnectionType":"Network"},{"Udid":"c2b1632e9949e742d81c5d4ef11d356bd4687014","ProductName":"iPhone OS","ProductType":"iPhone8,1","ProductVersion":"15.8.8","ConnectionType":"USB"}]}
''';

      final devices = IosDeviceService.parseDeviceListOutput(rawOutput);
      expect(devices.length, 1);
      final dev = devices.first;
      expect(dev.id, 'c2b1632e9949e742d81c5d4ef11d356bd4687014');
      expect(dev.model, 'iPhone OS (iPhone8,1)');
      expect(dev.product, '15.8.8');
      expect(dev.isIos, isTrue);
    });

    test('parseDeviceListOutput gracefully ignores invalid JSON and non-device lines', () {
      const invalidOutput = '''
some raw log output line
{"random":"json"}
{}
''';
      final devices = IosDeviceService.parseDeviceListOutput(invalidOutput);
      expect(devices, isEmpty);
    });
  });
}
