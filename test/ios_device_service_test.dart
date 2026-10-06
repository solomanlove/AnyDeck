import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/ios/ios_connection_type.dart';
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
      expect(dev.model, 'iPhone 6s');
      expect(dev.product, '15.8.8');
      expect(dev.isIos, isTrue);
      expect(dev.iosConnectionTypes, {IosConnectionType.usb, IosConnectionType.network});
    });

    test('Rust 设备字段使用相同的型号和版本解析', () {
      final device = IosDeviceService.parseDeviceListOutput(
        '[{"udid":"test-phone","name":"iPhone OS","model":"iPhone8,1","version":"iOS 15.8.8","connection_type":"Network"}]',
      ).single;
      expect(device.model, 'iPhone 6s');
      expect(device.product, '15.8.8');
      expect(device.iosConnectionTypes, {IosConnectionType.network});
    });

    test('未知型号保留硬件标识，缺失版本不写入占位缓存', () {
      final device = IosDeviceService.parseDeviceListOutput(
        '{"Udid":"test-phone","ProductType":"iPhone99,1","ProductVersion":"iOS"}',
      ).single;
      expect(device.model, 'iPhone99,1');
      expect(device.product, isNull);
      expect(device.iosConnectionTypes, isEmpty);
    });

    test('parseDeviceListOutput gracefully ignores invalid JSON and non-device lines', () {
      const invalidOutput = '''
some raw log output line
{"random":"json"}
{"level":"WARN","udid":"log-only-device","msg":"failed to get tunnel info"}
{}
''';
      final devices = IosDeviceService.parseDeviceListOutput(invalidOutput);
      expect(devices, isEmpty);
    });
  });
}
