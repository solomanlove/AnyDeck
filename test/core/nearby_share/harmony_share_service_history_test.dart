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
  Future<void> Function()? onStop;
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  void decide(bool accept) {}
  @override
  Future<void> stop() async {
    final callback = onStop;
    onStop = null;
    await callback?.call();
  }
}

class _Client extends Fake implements ShareCoreClient {
  final receiver = _Receiver();
  @override
  Future<ShareCoreReceiveSession> startInteractiveReceiver({
    required InternetAddress localAddress,
    required InternetAddress broadcastAddress,
    required Directory outputDirectory,
  }) async => receiver;
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('State not reached');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final result in [
    'success',
    'reject',
    'timeout',
    'coreTimeout',
    'failure',
    'lateSuccess',
  ]) {
    test('接收服务将 $result 保存为独立真实结果', () async {
      final root = await Directory.systemTemp.createTemp(
        'anydeck-service-history-',
      );
      final history = ShareTransferHistory(
        open: () =>
            Future.value(ShareHistoryDatabase('${root.path}/history.sqlite')),
      );
      final client = _Client();
      final service = HarmonyShareService.testing(
        client: client,
        history: history,
        detectNetwork: () async => ShareNetwork(
          InternetAddress('192.168.1.2'),
          InternetAddress('192.168.1.255'),
        ),
        downloads: () async => root,
      );
      try {
        await service.start();
        client.receiver.controller.add({'event': 'session_started'});
        client.receiver.controller.add({
          'event': 'incoming_offer',
          'ip': '192.168.1.3',
          'bytes': 100,
        });
        await _until(() => service.pendingOffer != null);
        if (result == 'success') {
          service.decide(true);
          client.receiver.controller.add({
            'event': 'file_received',
            'path': '${root.path}/received.bin',
            'bytes': 100,
            'sha256': 'a' * 64,
          });
          await _until(
            () => history.recent.single.status == ShareTransferStatus.succeeded,
          );
        } else if (result == 'lateSuccess') {
          service.decide(true);
          client.receiver.onStop = () async {
            client.receiver.controller.add({
              'event': 'file_received',
              'path': '${root.path}/late.bin',
              'bytes': 100,
            });
            await Future<void>.delayed(Duration.zero);
          };
        } else if (result == 'reject') {
          service.decide(false);
          client.receiver.controller.add({
            'event': 'error',
            'code': 'receive_failed',
            'reason': 'user_rejected',
          });
        } else if (result == 'timeout') {
          service.expireOffer(service.pendingOffer!);
          client.receiver.controller.add({
            'event': 'error',
            'code': 'receive_failed',
            'reason': 'user_rejected',
          });
        } else {
          client.receiver.controller.add({
            'event': 'error',
            'code': 'receive_failed',
            'reason': result == 'coreTimeout'
                ? 'decision_timeout'
                : 'network_lost',
          });
          await _until(() => service.pendingOffer == null);
        }
        await service.stop();
        final record = (await history.query()).single;
        expect(record.status, switch (result) {
          'success' || 'lateSuccess' => ShareTransferStatus.succeeded,
          'reject' => ShareTransferStatus.rejected,
          'timeout' || 'coreTimeout' => ShareTransferStatus.timedOut,
          _ => ShareTransferStatus.failed,
        });
        expect(record.direction, ShareTransferDirection.receive);
        if (result == 'lateSuccess') {
          expect(record.fileName, 'late.bin');
          expect(record.transferredBytes, 100);
        }
        if (result == 'success') {
          expect(record.fileName, 'received.bin');
          expect(record.transferredBytes, 100);
          expect(record.sha256, 'a' * 64);
        }
      } finally {
        await service.stop();
        await history.flush();
        await client.receiver.controller.close();
        service.dispose();
        history.dispose();
        await root.delete(recursive: true);
      }
    });
  }
}
