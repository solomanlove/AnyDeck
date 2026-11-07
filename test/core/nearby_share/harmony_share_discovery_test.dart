import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_network.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 显式控制真实 IPC 的就绪/失败顺序，不访问本机端口或启动蓝牙。
class _Receiver extends Fake implements ShareCoreReceiveSession {
  final output = StreamController<Map<String, dynamic>>();
  int stops = 0;
  @override
  Stream<Map<String, dynamic>> get events => output.stream;
  @override
  Future<void> stop() async {
    stops++;
  }
}

class _Client extends Fake implements ShareCoreClient {
  final receivers = <_Receiver>[];
  @override
  Future<ShareCoreReceiveSession> startBatchReceiver({
    required InternetAddress localAddress,
    required InternetAddress broadcastAddress,
    required Directory outputDirectory,
    String localName = 'AnyDeck',
  }) async {
    final receiver = _Receiver();
    receivers.add(receiver);
    return receiver;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  late _Client client;
  late HarmonyShareService service;
  setUp(() {
    client = _Client();
    service = HarmonyShareService.testing(
      client: client,
      nativeBatch: true,
      detectNetwork: () async => ShareNetwork(
        InternetAddress.loopbackIPv4,
        InternetAddress('127.255.255.255'),
      ),
      downloads: () async => Directory('/synthetic'),
    );
  });
  tearDown(() async {
    await service.stop();
    for (final receiver in client.receivers) {
      await receiver.output.close();
    }
    service.dispose();
  });
  Future<void> flush() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.value();
    }
  }

  test('接收进程创建不等于搜索，只有真实就绪才启动扫描动画', () async {
    await service.start();
    expect(service.startingDiscovery, isTrue);
    expect(service.scanning, isFalse);
    client.receivers.single.output.add({'event': 'discovery_ready'});
    await flush();
    expect(service.startingDiscovery, isFalse);
    expect(service.scanning, isTrue);
  });
  test('端口冲突立即结束搜索，保留原因；重新扫描后可恢复', () async {
    await service.start();
    client.receivers.single.output.add({
      'event': 'error',
      'code': 'receive_failed',
      'reason': 'discovery_port_in_use',
    });
    await flush();
    expect(service.error, 'receive_failed: discovery_port_in_use');
    expect(service.scanning, isFalse);
    expect(service.startingDiscovery, isFalse);
    await service.refresh();
    expect(service.startingDiscovery, isTrue);
    client.receivers.last.output.add({'event': 'discovery_ready'});
    await flush();
    expect(service.scanning, isTrue);
    expect(service.error, isNull);
  });
  test('启动挂起8秒后明确超时并清理进程，不进入1秒重试循环', () {
    fakeAsync((clock) {
      unawaited(service.start());
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 8));
      clock.flushMicrotasks();
      expect(service.error, 'receive_failed: discovery_start_timeout');
      expect(service.scanning, isFalse);
      expect(client.receivers.single.stops, 1);
      clock.elapse(const Duration(seconds: 5));
      clock.flushMicrotasks();
      expect(client.receivers.length, 1);
    });
  });
  test('就绪后不会触发启动超时，接收开始后停止发现状态', () {
    fakeAsync((clock) {
      unawaited(service.start());
      clock.flushMicrotasks();
      client.receivers.single.output.add({'event': 'discovery_ready'});
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 9));
      clock.flushMicrotasks();
      expect(service.scanning, isTrue);
      expect(service.error, isNull);
      client.receivers.single.output.add({'event': 'session_started'});
      clock.flushMicrotasks();
      expect(service.scanning, isFalse);
      expect(service.startingDiscovery, isFalse);
    });
  });
  test('主动停止排空期间迟到的就绪事件不能恢复搜索', () async {
    await service.start();
    final stopping = service.stop();
    client.receivers.single.output.add({'event': 'discovery_ready'});
    await stopping;
    await flush();
    expect(service.scanning, isFalse);
    expect(service.startingDiscovery, isFalse);
  });
  test('启动失败自然退出保留原因，不自动快速重试', () async {
    await service.start();
    final receiver = client.receivers.single;
    receiver.output.add({'event': 'error', 'code': 'receive_failed', 'reason': 'discovery_port_in_use'});
    await flush();
    await receiver.output.close();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(service.error, 'receive_failed: discovery_port_in_use');
    expect(service.scanning, isFalse);
    expect(client.receivers.length, 1);
  });
}
