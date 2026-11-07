import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';

/// 只覆盖握手能力门控；缺少直连能力时不得继续尝试启动原生进程。
class _LegacyCore extends ShareCoreClient {
  int probes = 0;

  @override
  Future<ShareCoreCapabilities> probe() async {
    probes++;
    return const ShareCoreCapabilities(
      discovery: true,
      send: false,
      receive: false,
      coreVersion: '0.3.0',
      maxFileBytes: ShareCoreContract.maxFileBytes,
    );
  }
}

void main() {
  test('只有显式布尔 true 声明直连，旧握手仍兼容 LAN', () {
    final experimental = <String, Object?>{
      'max_file_bytes': ShareCoreContract.maxFileBytes,
      'max_transfer_seconds': ShareCoreContract.transferTimeout.inSeconds,
      'progress': true,
      'graceful_cancel': true,
      'native_batch': true,
      'file_progress': true,
      'batch_local_name': true,
      'max_local_name_bytes': 24,
      'max_files': ShareBatchContract.maxFiles,
      'max_batch_bytes': ShareBatchContract.maxBytes,
    };
    final hello = <String, Object?>{
      'event': 'hello',
      'version': ShareCoreContract.version,
      'core_version': '0.3.0',
      'capabilities': {'discovery': true, 'send': false, 'receive': false},
      'experimental': experimental,
    };
    expect(ShareCoreCapabilities.parse(jsonEncode(hello)).directMode, isFalse);
    for (final declaration in <Object?>[false, null, 'true', 1, true]) {
      experimental['direct_mode'] = declaration;
      final capabilities = ShareCoreCapabilities.parse(jsonEncode(hello));
      expect(capabilities.directMode, declaration == true);
      expect(capabilities.discovery, isTrue);
    }
  });

  test('旧 Core 直连请求在启动进程前明确拒绝', () async {
    final client = _LegacyCore();
    await expectLater(
      client.startDirectBatchReceiver(
        localAddress: InternetAddress.loopbackIPv4,
        broadcastAddress: InternetAddress('127.255.255.255'),
        outputDirectory: Directory('/synthetic/not-started'),
      ),
      throwsA(
        isA<FormatException>().having(
          (failure) => failure.message,
          'message',
          'Share Core direct mode unavailable',
        ),
      ),
    );
    expect(client.probes, 1);
  });

  test('IPC 2 不静默降级，新版本需要完整批次声明', () {
    const hello =
        '{"event":"hello","version":3,"core_version":"0.3.0",'
        '"capabilities":{"discovery":true,"send":false,"receive":false},'
        '"experimental":{"max_file_bytes":${ShareCoreContract.maxFileBytes},"max_transfer_seconds":1800,"progress":true,"graceful_cancel":true,"native_batch":true,"file_progress":true,"batch_local_name":true,"max_local_name_bytes":24,"max_files":100,"max_batch_bytes":${ShareBatchContract.maxBytes}}}';
    expect(
      () => ShareCoreCapabilities.parse(
        hello.replaceFirst('"version":3', '"version":2'),
      ),
      throwsFormatException,
    );
    for (final change in [
      '"native_batch":false',
      '"file_progress":false',
      '"batch_local_name":false',
      '"max_local_name_bytes":25',
      '"max_files":101',
      '"max_batch_bytes":1',
    ]) {
      final field = change.split(':').first;
      final mutated = hello.replaceFirst(RegExp('$field:[^,}]+'), change);
      expect(() => ShareCoreCapabilities.parse(mutated), throwsFormatException);
    }
  });
  test('accepts explicit versioned capabilities', () {
    final result = ShareCoreCapabilities.parse(
      '{"event":"hello","version":3,"core_version":"0.1.0",'
      '"capabilities":{"discovery":false,"send":false,"receive":false},'
      '"experimental":{"max_file_bytes":${ShareCoreContract.maxFileBytes},"max_transfer_seconds":1800,"progress":true,"graceful_cancel":true,"native_batch":true,"file_progress":true,"batch_local_name":true,"max_local_name_bytes":24,"max_files":100,"max_batch_bytes":${ShareBatchContract.maxBytes}}}',
    );
    expect(result.send, isFalse);
    expect(result.coreVersion, '0.1.0');
  });

  test('rejects missing or incompatible capability declarations', () {
    expect(
      () => ShareCoreCapabilities.parse('{"event":"hello","version":3}'),
      throwsFormatException,
    );
    expect(
      () => ShareCoreCapabilities.parse(
        '{"event":"hello","version":3,"core_version":"0.1.0",'
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
    'rejects empty outgoing file before starting native transfer',
    () async {
      final folder = await Directory.systemTemp.createTemp('share-core-test-');
      try {
        final file = File('${folder.path}/large.bin');
        final handle = await file.open(mode: FileMode.write);
        await handle.truncate(0);
        await handle.close();
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
