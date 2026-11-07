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
  int starts = 0;
  late Directory directory;
  @override
  Future<ShareCoreReceiveSession> startBatchReceiver({
    required InternetAddress localAddress,
    required InternetAddress broadcastAddress,
    required Directory outputDirectory,
    String localName = 'AnyDeck',
  }) async {
    starts++;
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
  for (final reason in [
    'direct_network_restore_failed',
    'direct_network_restore_pending',
  ]) {
    test('恢复警告 $reason 保留成功文件与服务错误，结束后不自动重开', () async {
      final root = await Directory.systemTemp.createTemp('share-network-warning-');
      final database = ShareHistoryDatabase('${root.path}/history.sqlite');
      final history = ShareTransferHistory(open: () async => database);
      final client = _Client();
      final service = HarmonyShareService.testing(
        client: client,
        nativeBatch: true,
        history: history,
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
        service.decide(true);
        final id = history.recent.single.id;
        client.receiver.controller.add({
          'event': 'network_warning',
          'reason': reason,
        });
        await until(() => service.error != null);
        expect(history.recent.single.status, ShareTransferStatus.transferring);
        expect(history.recent.single.error, isNull);
        final files = [
          for (var index = 0; index < 2; index++)
            {
              'path': '${client.directory.path}/file-$index.bin',
              'bytes': index + 3,
              'sha256': 'a' * 64,
            },
        ];
        client.receiver.controller.add({
          'event': 'batch_received',
          'file_count': 2,
          'total_bytes': 7,
          'sender_hash_verified': false,
          'files': files,
        });
        await until(() => history.recent.single.terminal);
        await client.receiver.controller.close();
        await until(() => !service.busy);
        // 正常自然结束会在 1 秒后重开；恢复告警必须阻断这条自动路径。
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        await history.flush();
        final record = (await database.query()).single;
        expect(record.id, id);
        expect(record.status, ShareTransferStatus.succeeded);
        expect(record.error, isNull);
        expect(record.fileCount, 2);
        expect((await history.batchFiles(id)).length, 2);
        expect(service.recent, files.map((file) => file['path']));
        expect(service.error, 'receive_failed: $reason');
        expect(service.scanning, isFalse);
        expect(service.startingDiscovery, isFalse);
        expect(service.enabled, isTrue);
        expect(client.starts, 1);
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
  for (final accept in [true, false]) {
    test('接收文件进度仅在接受后展示，100%不结束批次，停止清空 $accept', () async {
      final root = await Directory.systemTemp.createTemp('receive-file-progress-');
      final client = _Client();
      final service = HarmonyShareService.testing(client: client, nativeBatch: true,
        downloads: () async => root,
        detectNetwork: () async => ShareNetwork(InternetAddress('192.168.1.2'), InternetAddress('192.168.1.255')));
      void emit(int bytes, {int total = 4}) => client.receiver.controller.add({
        'event':'file_progress','direction':'receive','index':1,'bytes':bytes,'total_bytes':total,
      });
      try {
        await service.start();
        client.receiver.controller.add({'event':'session_started'});
        client.receiver.controller.add({'event':'incoming_batch','ip':'192.168.1.3','file_count':2,'total_bytes':7});
        await until(() => service.pendingOffer != null);
        emit(2);
        await Future<void>.delayed(Duration.zero);
        expect(service.receiveFileProgress, isEmpty);
        service.decide(accept);
        emit(2);
        if (accept) {
          await until(() => service.receiveFileProgress.isNotEmpty);
          expect(service.receiveFileProgress.single.bytes, 2);
          emit(1); emit(3, total: 5);
          await Future<void>.delayed(Duration.zero);
          expect(service.receiveFileProgress.single.bytes, 2);
          emit(4);
          await until(() => service.receiveFileProgress.single.bytes == 4);
          expect(service.busy, isTrue);
          expect(service.receiving, isTrue);
        } else {
          await Future<void>.delayed(Duration.zero);
          expect(service.receiveFileProgress, isEmpty);
        }
        await service.stop();
        expect(service.receiveFileProgress, isEmpty);
      } finally {
        await service.stop(); service.dispose(); await client.receiver.controller.close();
        await root.delete(recursive: true);
      }
    });
  }
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
