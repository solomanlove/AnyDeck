import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:any_deck/features/harmony_share/model/harmony_share_peer_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// 旧Core只声明Huawei实验链；Honor请求必须在原生进程启动之前失败。
class _LegacyCore extends ShareCoreClient {
  int probes = 0;
  @override
  Future<ShareCoreCapabilities> probe() async {
    probes++;
    return const ShareCoreCapabilities(
      discovery: true,
      send: false,
      receive: false,
      coreVersion: 'synthetic',
      maxFileBytes: ShareCoreContract.maxFileBytes,
    );
  }
}

void main() {
  Map<String, dynamic> device({Object? protocol = 'huawei', int port = 5700}) =>
      {
        'event': 'device',
        'ip': '192.0.2.2',
        'port': port,
        'name': 'Same device',
        'protocol': protocol,
      };

  test('缺少协议字段沿用Huawei，显式协议仅接受白名单', () {
    final legacy = device()..remove('protocol');
    expect(ShareCorePeer.parse(legacy).protocol, ShareTransferProtocol.huawei);
    expect(
      ShareCorePeer.parse(device()).protocol,
      ShareTransferProtocol.huawei,
    );
    expect(
      ShareCorePeer.parse(device(protocol: 'honor')).protocol,
      ShareTransferProtocol.honor,
    );
    for (final value in [null, true, 1, 'Honor', 'honor ', 'unknown']) {
      expect(
        () => ShareCorePeer.parse(device(protocol: value)),
        throwsFormatException,
      );
    }
    expect(
      () => ShareCorePeer.parse(device(protocol: 'honor', port: 44800)),
      throwsFormatException,
    );
  });

  test('相同IP和名称的双协议设备不覆盖或继承彼此头像状态', () {
    final huawei = ShareCorePeer.parse(device());
    final honor = ShareCorePeer.parse(device(protocol: 'honor'));
    expect(huawei.key, '192.0.2.2');
    expect(honor.key, 'honor:192.0.2.2');
    final states = HarmonySharePeerState.resolve(peers: [huawei, honor]);
    expect(states.length, 2);
    expect(states.every((state) => state.available), isTrue);
    expect(
      states.map((state) => state.peer.protocol).toSet(),
      ShareTransferProtocol.values.toSet(),
    );
  });

  test('同一批次显式序列化协议，Honor端口必须匹配原生LAN入口', () {
    final batch = ShareBatchRequest([
      const ShareBatchFile('/synthetic/a.bin', 1024),
    ]);
    expect(
      batch.request(
        localIp: '192.0.2.1',
        peerIp: '192.0.2.2',
        port: 44800,
      )['protocol'],
      'huawei',
    );
    expect(
      batch.request(
        localIp: '192.0.2.1',
        peerIp: '192.0.2.2',
        port: 5700,
        protocol: ShareTransferProtocol.honor,
      )['protocol'],
      'honor',
    );
    expect(
      () => batch.request(
        localIp: '192.0.2.1',
        peerIp: '192.0.2.2',
        port: 44800,
        protocol: ShareTransferProtocol.honor,
      ),
      throwsFormatException,
    );
  });

  test('hello Honor实验能力必须是bool，不提升生产收发声明', () {
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
    String hello() => jsonEncode({
      'event': 'hello',
      'version': 3,
      'core_version': 'synthetic',
      'capabilities': {'discovery': true, 'send': false, 'receive': false},
      'experimental': experimental,
    });
    expect(ShareCoreCapabilities.parse(hello()).honor, isFalse);
    for (final value in [false, true]) {
      experimental['honor'] = value;
      final capabilities = ShareCoreCapabilities.parse(hello());
      expect(capabilities.honor, value);
      expect(capabilities.send, isFalse);
      expect(capabilities.receive, isFalse);
    }
    for (final value in [null, 1, 'true']) {
      experimental['honor'] = value;
      expect(() => ShareCoreCapabilities.parse(hello()), throwsFormatException);
    }
  });

  test('缺少Honor能力及旧单文件入口都不启动错误的协议链', () async {
    final client = _LegacyCore();
    final peer = ShareCorePeer.parse(device(protocol: 'honor'));
    await expectLater(
      client.sendBatchForTest(
        localAddress: InternetAddress('192.0.2.1'),
        peer: peer,
        request: ShareBatchRequest([
          const ShareBatchFile('/synthetic/a.bin', 1),
        ]),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Share Core Honor unavailable',
        ),
      ),
    );
    expect(client.probes, 1);
    await expectLater(
      client.sendFileForTest(
        localAddress: InternetAddress('192.0.2.1'),
        peer: peer,
        file: File('/synthetic/not-accessed'),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Share Core native batch required',
        ),
      ),
    );
  });

  test('记录保留Honor协议，旧记录缺字段默认Huawei，非法记录不参与重试', () {
    final record = ShareTransferRecord(
      id: 'synthetic',
      direction: ShareTransferDirection.send,
      status: ShareTransferStatus.failed,
      deviceName: 'Magic V6',
      address: '192.0.2.2',
      fileName: 'fixture.bin',
      bytes: 1024,
      createdAt: DateTime(2026),
      protocol: ShareTransferProtocol.honor,
    );
    expect(
      ShareTransferRecord.fromMap(
        record.update(transferredBytes: 3).toMap(),
      ).protocol,
      ShareTransferProtocol.honor,
    );
    expect(
      ShareTransferRecord.fromMap(record.toMap()..remove('protocol')).protocol,
      ShareTransferProtocol.huawei,
    );
    expect(
      () =>
          ShareTransferRecord.fromMap({...record.toMap(), 'protocol': 'other'}),
      throwsFormatException,
    );
  });
}
