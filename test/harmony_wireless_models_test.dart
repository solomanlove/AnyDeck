import 'package:any_deck/core/harmony/hdc_remote_server.dart';
import 'package:any_deck/core/harmony/wireless/harmony_wireless_models.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Harmony wireless endpoint validation', () {
    test('normalizes valid IPv4 and port', () {
      expect(
        normalizeHarmonyEndpoint(' 192.168.1.10:43210 '),
        '192.168.1.10:43210',
      );
    });

    test('rejects malformed, out-of-range and injected endpoints', () {
      expect(normalizeHarmonyEndpoint('192.168.1.10'), isNull);
      expect(normalizeHarmonyEndpoint('192.168.1.999:5555'), isNull);
      expect(normalizeHarmonyEndpoint('192.168.1.10:70000'), isNull);
      expect(normalizeHarmonyEndpoint('192.168.1.10:5555;reboot'), isNull);
    });
  });

  group('Remote HDC server address validation', () {
    test('accepts loopback and explicit IPv4 listeners', () {
      expect(
        HdcRemoteServer.normalizeServerAddress('127.0.0.1', 18710),
        '127.0.0.1:18710',
      );
      expect(
        HdcRemoteServer.normalizeServerAddress('0.0.0.0', 8710),
        '0.0.0.0:8710',
      );
    });

    test('rejects hostnames, injected addresses and invalid ports', () {
      expect(HdcRemoteServer.normalizeServerAddress('localhost', 8710), isNull);
      expect(
        HdcRemoteServer.normalizeServerAddress('127.0.0.1;id', 8710),
        isNull,
      );
      expect(HdcRemoteServer.normalizeServerAddress('127.0.0.1', 0), isNull);
    });
  });

  test('HarmonyOS treats every IP:Port HDC route as a TCP channel', () {
    const device = RegisteredDevice(
      id: '192.168.1.10:43210',
      status: 'device',
      isOnline: true,
      isHarmony: true,
      connections: ['USB-SERIAL', '192.168.1.10:43210'],
    );
    expect(device.hasUsbConnection, isTrue);
    expect(device.hasTcpConnection, isTrue);
    expect(device.preferredCommandId, 'USB-SERIAL');
  });
}
