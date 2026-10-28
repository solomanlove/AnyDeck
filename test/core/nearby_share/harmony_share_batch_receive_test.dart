import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_history_database.dart';
import 'package:any_deck/core/nearby_share/share_network.dart';
import 'package:any_deck/core/nearby_share/share_transfer_history.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Receiver extends Fake implements ShareCoreReceiveSession {
  final controller = StreamController<Map<String, dynamic>>();
  final decisions = <bool>[];
  Future<void> Function()? onStop;
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  void decide(bool accept) {
    decisions.add(accept);
  }

  @override
  Future<void> stop() async {
    final callback = onStop;
    onStop = null;
    await callback?.call();
  }
}

class _Client extends Fake implements ShareCoreClient {
  final receiver = _Receiver();
  late Directory directory;
  @override
  Future<ShareCoreReceiveSession> startBatchReceiver({
    required InternetAddress localAddress,
    required InternetAddress broadcastAddress,
    required Directory outputDirectory,
  }) async {
    directory = outputDirectory;
    return receiver;
  }
}

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('state not reached');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final mode in [
    'success',
    'reject',
    'timeout',
    'invalid',
    'lateSuccess',
  ]) {
    test('原生批次 $mode 保存摘要/子文件，重开可查询', () async {
      final root = await Directory.systemTemp.createTemp(
        'share-batch-service-',
      );
      final database = ShareHistoryDatabase('${root.path}/history.sqlite');
      final history = ShareTransferHistory(open: () async => database);
      final client = _Client();
      final service = HarmonyShareService.testing(
        client: client,
        history: history,
        nativeBatch: true,
        downloads: () async => root,
        detectNetwork: () async => ShareNetwork(
          InternetAddress('192.168.1.2'),
          InternetAddress('192.168.1.255'),
        ),
      );
      try {
        await service.start();
        client.receiver.controller.add({'event': 'session_started'});
        client.receiver.controller.add({
          'event': 'incoming_batch',
          'ip': '192.168.1.3',
          'file_count': 2,
          'total_bytes': 7,
        });
        await until(() => service.pendingOffer != null);
        expect(service.pendingOffer!.fileCount, 2);
        final id = history.recent.single.id;
        final files = [
          for (var i = 0; i < 2; i++)
            {
              'path': '${client.directory.path}/file-$i.bin',
              'bytes': i + 3,
              'sha256': 'a' * 64,
            },
        ];
        final event = {
          'event': 'batch_received',
          'file_count': 2,
          'total_bytes': 7,
          'sender_hash_verified': false,
          'files': mode == 'invalid' ? files.take(1).toList() : files,
        };
        if (mode == 'reject') {
          service.decide(false);
        } else if (mode == 'timeout') {
          service.expireOffer(service.pendingOffer!);
        } else {
          service.decide(true);
          if (mode == 'lateSuccess') {
            client.receiver.onStop = () async {
              client.receiver.controller.add(event);
              await Future<void>.delayed(Duration.zero);
            };
            service.cancelTransfer();
          } else {
            client.receiver.controller.add(event);
          }
        }
        await until(() => history.recent.single.terminal);
        await service.stop();
        await history.flush();
        final rows = await database.query();
        expect(rows.length, 1);
        expect(rows.single.fileCount, 2);
        final expected = switch (mode) {
          'reject' => ShareTransferStatus.rejected,
          'timeout' => ShareTransferStatus.timedOut,
          'invalid' => ShareTransferStatus.failed,
          _ => ShareTransferStatus.succeeded,
        };
        expect(rows.single.status, expected);
        final children = await history.batchFiles(id);
        expect(
          children.length,
          expected == ShareTransferStatus.succeeded ? 2 : 0,
        );
        if (children.isNotEmpty) {
          expect(children.map((file) => file.bytes), [3, 4]);
          expect(children.every((file) => file.batchId == id), isTrue);
          expect(children.every((file) => file.sha256 == 'a' * 64), isTrue);
          final reopened = ShareTransferHistory(open: () async => database);
          await reopened.initialize();
          expect(reopened.recent.single.fileCount, 2);
          expect((await reopened.batchFiles(id)).length, 2);
          reopened.dispose();
          await database.remove(id);
          expect(await database.batchFiles(id), isEmpty);
        }
      } finally {
        await service.stop();
        await history.flush();
        service.dispose();
        history.dispose();
        await client.receiver.controller.close();
        await root.delete(recursive: true);
      }
    });
  }
}
