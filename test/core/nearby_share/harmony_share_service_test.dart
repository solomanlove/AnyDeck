import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_network.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Session extends Fake implements ShareCoreReceiveSession {
  final controller = StreamController<Map<String, dynamic>>();
  int stops = 0;
  bool? accepted;
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  void decide(bool accept) => accepted = accept;
  @override
  Future<void> stop() async {
    stops++;
  }
}

class _Client extends Fake implements ShareCoreClient {
  final session = _Session();
  int starts = 0;
  Completer<ShareCoreReceiveSession>? gate;
  int sends = 0;
  @override
  Future<ShareCoreTransfer> sendFileForTest({
    required InternetAddress localAddress,
    required ShareCorePeer peer,
    required File file,
  }) async {
    sends++;
    throw StateError('Unexpected send');
  }

  @override
  Future<ShareCoreReceiveSession> startInteractiveReceiver({
    required InternetAddress localAddress,
    required InternetAddress broadcastAddress,
    required Directory outputDirectory,
  }) async {
    starts++;
    return gate == null ? session : await gate!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('接收大文件期间不被125秒发现 watchdog终止，停止后释放监听', () async {
    late _Client client;
    late HarmonyShareService service;
    fakeAsync((clock) {
      client = _Client();
      service = HarmonyShareService.testing(
        client: client,
        detectNetwork: () async => ShareNetwork(
          InternetAddress('192.168.1.2'),
          InternetAddress('192.168.1.255'),
        ),
        downloads: () async => Directory('/tmp'),
      );
      unawaited(service.start());
      clock.flushMicrotasks();
      expect(client.starts, 1);
      client.session.controller.add({
        'event': 'session_started',
        'direction': 'receive',
      });
      client.session.controller.add({
        'event': 'incoming_offer',
        'ip': '192.168.1.3',
        'bytes': 100 * 1024 * 1024,
      });
      clock.flushMicrotasks();
      expect(service.busy, isTrue);
      expect(service.pendingOffer!.bytes, 100 * 1024 * 1024);
      service.decide(true);
      expect(client.session.accepted, isTrue);
      clock.elapse(const Duration(seconds: 126));
      clock.flushMicrotasks();
      expect(client.session.stops, 0);
      client.session.controller.add({
        'event': 'progress',
        'direction': 'receive',
        'bytes': 1024,
        'total_bytes': 2048,
      });
      clock.flushMicrotasks();
      expect(service.progress!.fraction, .5);
      client.session.controller.add({
        'event': 'progress',
        'direction': 'receive',
        'bytes': 512,
        'total_bytes': 2048,
      });
      clock.flushMicrotasks();
      expect(service.progress!.bytes, 1024);
    });
    await service.stop();
    expect(client.session.stops, 1);
    expect(service.busy, isFalse);
    expect(service.progress, isNull);
    await client.session.controller.close();
    service.dispose();
  });
  test('准备期间取消不会稍后启动发送进程', () async {
    final client = _Client();
    final service = HarmonyShareService.testing(
      client: client,
      detectNetwork: () async => ShareNetwork(
        InternetAddress('192.168.1.2'),
        InternetAddress('192.168.1.255'),
      ),
      downloads: () async => Directory('/tmp'),
    );
    final sending = service.send(
      ShareCorePeer(
        address: InternetAddress('192.168.1.3'),
        port: 44800,
        name: 'test',
      ),
      File('/tmp/not-read'),
    );
    service.cancelTransfer();
    await sending;
    expect(client.sends, 0);
    expect(service.error, contains('cancelled'));
    expect(service.busy, isFalse);
    service.dispose();
  });
  test('启动尚未完成时停止，不留下迟到的接收进程', () async {
    final client = _Client()..gate = Completer<ShareCoreReceiveSession>();
    final service = HarmonyShareService.testing(
      client: client,
      detectNetwork: () async => ShareNetwork(
        InternetAddress('192.168.1.2'),
        InternetAddress('192.168.1.255'),
      ),
      downloads: () async => Directory('/tmp'),
    );
    final starting = service.start();
    while (client.starts == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final stopping = service.stop();
    client.gate!.complete(client.session);
    await starting;
    await stopping;
    expect(client.session.stops, 1);
    expect(service.enabled, isFalse);
    unawaited(client.session.controller.close());
    service.dispose();
  });
}
