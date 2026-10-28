import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/harmony_share_send_queue.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_history_database.dart';
import 'package:any_deck/core/nearby_share/share_network.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:any_deck/core/nearby_share/share_transfer_history.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Receiver extends Fake implements ShareCoreReceiveSession {
  final stream = StreamController<Map<String, dynamic>>();
  int stops = 0;
  @override
  Stream<Map<String, dynamic>> get events => stream.stream;
  @override
  Future<void> stop() async {
    stops++;
  }
}

class _Transfer extends Fake implements ShareBatchTransfer {
  final stream = StreamController<ShareCoreProgress>.broadcast();
  final done = Completer<Map<String, dynamic>>();
  int cancels = 0;
  bool lateSuccess = false;
  @override
  Stream<ShareCoreProgress> get progress => stream.stream;
  @override
  Future<Map<String, dynamic>> get result => done.future;
  @override
  void cancel() {
    cancels++;
    if (!lateSuccess && !done.isCompleted) {
      done.completeError(StateError('cancelled'));
    }
  }
}

class _Client extends Fake implements ShareCoreClient {
  final receivers = <_Receiver>[];
  final transfer = _Transfer();
  Completer<void>? launching;
  ShareBatchRequest? request;
  @override
  Future<ShareCoreReceiveSession> startBatchReceiver({
    required InternetAddress localAddress,
    required InternetAddress broadcastAddress,
    required Directory outputDirectory,
  }) async {
    final result = _Receiver();
    receivers.add(result);
    return result;
  }

  @override
  Future<ShareBatchTransfer> sendBatchForTest({
    required InternetAddress localAddress,
    required ShareCorePeer peer,
    required ShareBatchRequest request,
  }) async {
    this.request = request;
    await launching?.future;
    return transfer;
  }
}

Future<void> until(bool Function() test) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!test()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('state missing');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final mode in [
    'success',
    'failure',
    'cancel',
    'lateSuccess',
    'launchCancel',
    'changed',
    'nameConflict',
    'networkCancel',
    'stop',
  ]) {
    test('原生发送服务 $mode：一次 IPC、批次记录和独立文件结果', () async {
      final root = await Directory.systemTemp.createTemp('native-send-');
      final database = ShareHistoryDatabase('${root.path}/history.sqlite');
      final history = ShareTransferHistory(open: () async => database);
      final client = _Client();
      final detecting = Completer<void>();
      final detected = Completer<void>();
      final service = HarmonyShareService.testing(
        client: client,
        nativeBatch: true,
        history: history,
        downloads: () async => root,
        detectNetwork: () async {
          if (mode == 'networkCancel' &&
              client.receivers.isNotEmpty &&
              !detected.isCompleted) {
            detecting.complete();
            await detected.future;
          }
          return ShareNetwork(
            InternetAddress('192.168.1.2'),
            InternetAddress('192.168.1.255'),
          );
        },
      );
      try {
        final files = [
          await File('${root.path}/first.bin').writeAsBytes([1, 2, 3]),
          await File('${root.path}/second.bin').writeAsBytes([4, 5, 6, 7]),
        ];
        if (mode == 'nameConflict') {
          final other = await Directory('${root.path}/other').create();
          files[1] = await File('${other.path}/FIRST.bin').writeAsBytes([1]);
        }
        final selection = await ShareSendSelection.inspect(files);
        if (mode == 'changed') await files.last.writeAsBytes([1]);
        client.transfer.lateSuccess = mode == 'lateSuccess';
        if (mode == 'launchCancel') client.launching = Completer<void>();
        await service.start();
        final run = service.sendSelection(
          ShareCorePeer(
            address: InternetAddress('192.168.1.3'),
            port: 44800,
            name: 'fixture',
          ),
          selection,
          retryOf: 'old-id',
        );
        if (mode == 'networkCancel') {
          await detecting.future;
          service.cancelTransfer();
          detected.complete();
        } else if (mode != 'changed' && mode != 'nameConflict') {
          await until(() => client.request != null);
          expect(client.request!.files.length, 2);
          expect(client.receivers.single.stops, 1);
          expect(service.busy, isTrue);
          if (mode == 'launchCancel') {
            service.cancelTransfer();
            client.launching!.complete();
          } else {
            client.transfer.stream.add(
              const ShareCoreProgress(
                direction: 'send',
                bytes: 4,
                totalBytes: 7,
              ),
            );
            await until(() => service.sendQueue.transferredBytes == 4);
            expect(
              service.sendQueue.items.every(
                (item) => item.transferredBytes == 0,
              ),
              isTrue,
            );
            if (mode == 'cancel' || mode == 'lateSuccess') {
              service.cancelTransfer();
            }
            if (mode == 'stop') await service.stop();
            if (mode == 'failure') {
              client.transfer.done.completeError(StateError('phone rejected'));
            } else if (mode == 'success' || mode == 'lateSuccess') {
              client.transfer.done.complete({
                'event': 'batch_sent',
                'file_count': 2,
                'total_bytes': 7,
                'remote_hash_verified': false,
              });
            }
          }
        }
        await run;
        expect(client.receivers.length, mode == 'stop' ? 1 : 2);
        expect(service.busy, isFalse);
        await history.flush();
        final summary = (await database.query()).single;
        final success = mode == 'success' || mode == 'lateSuccess';
        final cancelled = [
          'cancel',
          'launchCancel',
          'networkCancel',
          'stop',
        ].contains(mode);
        expect(
          summary.status,
          success
              ? ShareTransferStatus.succeeded
              : cancelled
              ? ShareTransferStatus.cancelled
              : ShareTransferStatus.failed,
        );
        expect(summary.fileCount, 2);
        expect(summary.path, isNull);
        expect(summary.retryOf, 'old-id');
        expect(
          summary.transferredBytes,
          success
              ? 7
              : mode == 'failure' || mode == 'cancel' || mode == 'stop'
              ? 4
              : 0,
        );
        final children = await history.batchFiles(summary.id);
        expect(children.length, 2);
        expect(children.every((item) => item.status == summary.status), isTrue);
        expect(
          children.map((item) => item.transferredBytes),
          success ? [3, 4] : [0, 0],
        );
        expect(children.every((item) => item.sha256 == null), isTrue);
        expect(children.every((item) => item.retryOf == 'old-id'), isTrue);
        if ((cancelled && mode != 'networkCancel') || mode == 'lateSuccess') {
          expect(client.transfer.cancels, 1);
        }
        if (mode == 'changed' ||
            mode == 'nameConflict' ||
            mode == 'networkCancel') {
          expect(client.request, isNull);
        }
        expect(service.recent.length, success ? 2 : 0);
        expect(
          service.sendQueue.count(
            success
                ? ShareSendStatus.succeeded
                : cancelled
                ? ShareSendStatus.cancelled
                : ShareSendStatus.failed,
          ),
          2,
        );
        final reopened = ShareTransferHistory(open: () async => database);
        await reopened.initialize();
        expect(reopened.recent.single.id, summary.id);
        expect((await reopened.batchFiles(summary.id)).length, 2);
        reopened.dispose();
      } finally {
        await service.stop();
        await history.flush();
        service.dispose();
        history.dispose();
        for (final receiver in client.receivers) {
          await receiver.stream.close();
        }
        await client.transfer.stream.close();
        await root.delete(recursive: true);
      }
    });
  }
}
