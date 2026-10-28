import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Receiver extends Fake implements ShareCoreReceiveSession {
  final eventsController = StreamController<Map<String, dynamic>>();
  int stops = 0;
  @override
  Stream<Map<String, dynamic>> get events => eventsController.stream;
  @override
  Future<void> stop() async {
    stops++;
  }
}

class _Transfer extends Fake implements ShareCoreTransfer {
  final updates = StreamController<ShareCoreProgress>();
  final done = Completer<Map<String, dynamic>>();
  @override
  Stream<ShareCoreProgress> get progress => updates.stream;
  @override
  Future<Map<String, dynamic>> get result => done.future;
  @override
  void cancel() {
    if (!done.isCompleted) done.completeError(StateError('cancelled'));
    unawaited(updates.close());
  }

  Future<void> finish() async {
    done.complete({'event': 'file_sent', 'remote_hash_verified': false});
    await updates.close();
  }
}

class _Client extends Fake implements ShareCoreClient {
  final receivers = <_Receiver>[];
  final transfers = <_Transfer>[];
  @override
  Future<ShareCoreReceiveSession> startInteractiveReceiver({
    required InternetAddress localAddress,
    required InternetAddress broadcastAddress,
    required Directory outputDirectory,
  }) async {
    final receiver = _Receiver();
    receivers.add(receiver);
    return receiver;
  }

  @override
  Future<ShareCoreTransfer> sendFileForTest({
    required InternetAddress localAddress,
    required ShareCorePeer peer,
    required File file,
  }) async {
    final transfer = _Transfer();
    transfers.add(transfer);
    return transfer;
  }
}

Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Test state did not arrive');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('多文件串行期间不重启接收，整个队列结束后恢复一次', () async {
    final root = await Directory.systemTemp.createTemp('anydeck-batch-test-');
    final client = _Client();
    final service = HarmonyShareService.testing(
      client: client,
      detectNetwork: () async => ShareNetwork(
        InternetAddress('192.168.1.2'),
        InternetAddress('192.168.1.255'),
      ),
      downloads: () async => root,
    );
    try {
      final files = [
        await File('${root.path}/a.bin').writeAsBytes([1]),
        await File('${root.path}/b.bin').writeAsBytes([2]),
      ];
      await service.start();
      final batch = service.sendFiles(
        ShareCorePeer(
          address: InternetAddress('192.168.1.3'),
          port: 44800,
          name: 'test',
        ),
        files,
      );
      await _until(() => client.transfers.length == 1);
      expect(client.receivers.single.stops, 1);
      client.transfers.first.updates.add(
        const ShareCoreProgress(direction: 'send', bytes: 1, totalBytes: 1),
      );
      await _until(() => service.progress != null);
      expect(service.sendQueue.finished, 0);
      await client.transfers.first.finish();
      await _until(() => client.transfers.length == 2);
      expect(service.busy, isTrue);
      expect(client.receivers.length, 1);
      await client.transfers.last.finish();
      await batch;
      expect(client.receivers.length, 2);
      expect(service.sendQueue.finished, 2);
      expect(service.recent.length, 2);
      expect(service.busy, isFalse);
    } finally {
      await service.stop();
      for (final receiver in client.receivers) {
        await receiver.eventsController.close();
      }
      service.dispose();
      await root.delete(recursive: true);
    }
  });
}
