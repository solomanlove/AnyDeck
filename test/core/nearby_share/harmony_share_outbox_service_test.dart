import 'dart:async';
import 'dart:io';
import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_history_database.dart';
import 'package:any_deck/core/nearby_share/share_network.dart';
import 'package:any_deck/core/nearby_share/share_send_selection.dart';
import 'package:any_deck/core/nearby_share/share_transfer_history.dart';
import 'package:any_deck/core/nearby_share/share_transfer_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Receiver extends Fake implements ShareCoreReceiveSession {
  final stream = StreamController<Map<String, dynamic>>();
  int stops = 0;
  Future<void> Function()? onStop;
  @override
  Stream<Map<String, dynamic>> get events => stream.stream;
  @override
  Future<void> stop() async {
    stops++;
    await onStop?.call();
  }
}

class _Transfer extends Fake implements ShareBatchTransfer {
  final done = Completer<Map<String, dynamic>>();
  final updates = StreamController<ShareCoreProgress>.broadcast();
  @override
  Stream<ShareCoreProgress> get progress => updates.stream;
  @override
  Future<Map<String, dynamic>> get result => done.future;
  @override
  void cancel() {
    if (!done.isCompleted) done.completeError(StateError('cancelled'));
  }
}

class _Client extends Fake implements ShareCoreClient {
  final receivers = <_Receiver>[];
  final transfers = <_Transfer>[];
  @override
  Future<ShareCoreReceiveSession> startBatchReceiver({
    required InternetAddress localAddress,
    required InternetAddress broadcastAddress,
    required Directory outputDirectory,
  }) async {
    final item = _Receiver();
    receivers.add(item);
    return item;
  }

  @override
  Future<ShareBatchTransfer> sendBatchForTest({
    required InternetAddress localAddress,
    required ShareCorePeer peer,
    required ShareBatchRequest request,
  }) async {
    final item = _Transfer();
    transfers.add(item);
    return item;
  }
}

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('state missing');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

class _LateService extends HarmonyShareService {
  _LateService(_Client client)
    : super.testing(
        client: client,
        nativeBatch: true,
        downloads: () async => Directory('/synthetic'),
        detectNetwork: () async => ShareNetwork(
          InternetAddress.loopbackIPv4,
          InternetAddress('127.255.255.255'),
        ),
      );
  int expired = 0;
  @override
  void cancelTransfer() {
    expired++;
    super.cancelTransfer();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('停止排空期间的迟到来件 watchdog 不会在后续长队列中触发', () async {
    SharedPreferences.setMockInitialValues({});
    late FakeAsync clock;
    late _Client client;
    late _LateService service;
    var stopped = false;
    fakeAsync((value) {
      clock = value;
      client = _Client();
      service = _LateService(client);
      unawaited(service.start());
      clock.flushMicrotasks();
      client.receivers.single.onStop = () async {
        client.receivers.single.stream.add({'event': 'session_started'});
      };
      unawaited(service.stop().then((_) => stopped = true));
      clock.flushMicrotasks();
    });
    // Stream.cancel 的共享完成 Future 可能来自外层 Zone，先让真实微任务排空。
    await Future<void>.delayed(Duration.zero);
    clock.flushMicrotasks();
    expect(stopped, isTrue);
    clock.elapse(const Duration(hours: 1));
    expect(service.expired, 0);
    service.dispose();
    unawaited(client.receivers.single.stream.close());
    clock.flushMicrotasks();
  });

  for (final mode in [
    'continue',
    'cancelPending',
    'cancelAll',
    'changed',
    'lateIncoming',
    'cancelActive',
  ]) {
    test('原生追加服务 $mode：排队先落盘、单会话和一次恢复接收', () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('outbox-service-');
      final db = ShareHistoryDatabase('${root.path}/history.sqlite');
      final history = ShareTransferHistory(open: () async => db);
      final client = _Client();
      final service = HarmonyShareService.testing(
        client: client,
        history: history,
        nativeBatch: true,
        downloads: () async => root,
        detectNetwork: () async => ShareNetwork(
          InternetAddress.loopbackIPv4,
          InternetAddress('127.255.255.255'),
        ),
      );
      try {
        final files = [
          for (var i = 0; i < 3; i++)
            await File('${root.path}/$i.bin').writeAsBytes([i + 1]),
        ];
        final peer = ShareCorePeer(
          address: InternetAddress.loopbackIPv4,
          port: 1234,
          name: 'fixture',
        );
        await service.start();
        if (mode == 'lateIncoming') {
          client.receivers.first.onStop = () async {
            client.receivers.first.stream.add({'event': 'session_started'});
            await Future<void>.delayed(Duration.zero);
          };
        }
        final first = service.sendSelection(
          peer,
          await ShareSendSelection.inspect([files.first]),
        );
        await until(() => client.transfers.length == 1);
        expect(service.canAppend, isTrue);
        await service.appendSelection(
          peer,
          await ShareSendSelection.inspect(files.sublist(1)),
          retryOf: 'earlier-task',
        );
        final queuedId = 'send-${service.outbox.waiting.single.id}';
        final before = await history.query();
        expect(before.length, 2);
        expect(
          before.firstWhere((row) => row.id == queuedId).status,
          ShareTransferStatus.queued,
        );
        expect(client.transfers.length, 1);
        expect(client.receivers.single.stops, 1);
        if (mode == 'cancelPending') {
          service.outbox.cancel(service.outbox.waiting.single.id);
        } else if (mode == 'cancelAll') {
          service.cancelTransfer();
          expect(service.canAppend, isFalse);
        } else if (mode == 'changed') {
          await files.last.writeAsBytes([1, 2]);
        }
        if (mode == 'continue' ||
            mode == 'lateIncoming' ||
            mode == 'cancelActive') {
          if (mode == 'continue') {
            client.transfers.first.done.completeError(
              StateError('first batch failed'),
            );
          } else if (mode == 'cancelActive') {
            service.sendQueue.cancelAll();
            expect(service.canAppend, isTrue);
          } else {
            client.transfers.first.done.complete({'event': 'batch_sent'});
          }
          await until(() => client.transfers.length == 2);
          expect(client.receivers.length, 1);
          client.transfers.last.done.complete({'event': 'batch_sent'});
        } else if (mode != 'cancelAll') {
          client.transfers.first.done.complete({'event': 'batch_sent'});
        }
        await first;
        expect(client.receivers.length, 2);
        expect(service.busy, isFalse);
        final after = await history.query();
        expect(after.length, 2);
        final second = after.firstWhere((row) => row.id == queuedId);
        final expected = switch (mode) {
          'continue' ||
          'lateIncoming' ||
          'cancelActive' => ShareTransferStatus.succeeded,
          'changed' => ShareTransferStatus.failed,
          _ => ShareTransferStatus.cancelled,
        };
        expect(second.status, expected);
        expect(second.retryOf, 'earlier-task');
        expect(
          (await history.batchFiles(
            queuedId,
          )).every((row) => row.status == expected),
          isTrue,
        );
        expect(
          client.transfers.length,
          mode == 'continue' || mode == 'lateIncoming' || mode == 'cancelActive'
              ? 2
              : 1,
        );
        expect(
          service.outbox.succeeded,
          mode == 'lateIncoming'
              ? 3
              : (mode == 'continue' || mode == 'cancelActive')
              ? 2
              : mode == 'cancelAll'
              ? 0
              : 1,
        );
        expect(
          service.outbox.failed,
          mode == 'continue'
              ? 1
              : mode == 'changed'
              ? 2
              : 0,
        );
        expect(
          service.outbox.cancelled,
          mode == 'cancelAll'
              ? 3
              : mode == 'cancelPending'
              ? 2
              : mode == 'cancelActive'
              ? 1
              : 0,
        );
      } finally {
        await service.stop();
        service.dispose();
        history.dispose();
        for (final receiver in client.receivers) {
          await receiver.stream.close();
        }
        for (final transfer in client.transfers) {
          await transfer.updates.close();
        }
        await root.delete(recursive: true);
      }
    });
  }
}
