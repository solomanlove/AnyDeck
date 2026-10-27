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

  test(
    'rejects oversized outgoing file before starting native transfer',
    () async {
      final folder = await Directory.systemTemp.createTemp('share-core-test-');
      try {
        final file = File('${folder.path}/large.bin');
        await file.writeAsBytes(List.filled(1024 * 1024 + 1, 0));
        expect(
          () => const ShareCoreClient().sendFileForTest(
            localAddress: InternetAddress('192.168.1.2'),
            peer: ShareCorePeer(
              address: InternetAddress('192.168.1.3'),
              port: 44800,
              name: 'phone',
            ),
            file: file,
          ),
          throwsFormatException,
        );
      } finally {
        await folder.delete(recursive: true);
      }
    },
  );

  test('refuses an existing receive directory', () async {
    final folder = await Directory.systemTemp.createTemp('share-core-receive-');
    try {
      expect(
        () => const ShareCoreClient().receiveFileForTest(
          localAddress: InternetAddress('192.168.1.2'),
          broadcastAddress: InternetAddress('192.168.1.255'),
          peerAddress: InternetAddress('192.168.1.3'),
          outputDirectory: folder,
        ),
        throwsFormatException,
      );
    } finally {
      await folder.delete(recursive: true);
    }
  });
}
