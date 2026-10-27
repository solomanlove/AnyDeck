import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';

void main() {
  test('accepts explicit versioned capabilities', () {
    final result = ShareCoreCapabilities.parse(
      '{"event":"hello","version":1,"core_version":"0.1.0",'
      '"capabilities":{"discovery":false,"send":false,"receive":false}}',
    );
    expect(result.send, isFalse);
    expect(result.coreVersion, '0.1.0');
  });

  test('rejects missing or incompatible capability declarations', () {
    expect(
      () => ShareCoreCapabilities.parse('{"event":"hello","version":2}'),
      throwsFormatException,
    );
    expect(
      () => ShareCoreCapabilities.parse(
        '{"event":"hello","version":1,"core_version":"0.1.0",'
        '"capabilities":{"discovery":true,"send":"yes","receive":false}}',
      ),
      throwsFormatException,
    );
  });

  test('validates discovered peer fields before exposing them to the UI', () {
    final peer = ShareCorePeer.parse({
      'event': 'device',
      'ip': '192.168.31.146',
      'port': 44800,
      'name': 'nova 12 Ultra',
    });
    expect(peer.address, InternetAddress('192.168.31.146'));
    expect(peer.port, 44800);
    expect(
      () => ShareCorePeer.parse({
        'event': 'device',
        'ip': 'not-an-ip',
        'port': 44800,
        'name': 'phone',
      }),
      throwsFormatException,
    );
  });
}
