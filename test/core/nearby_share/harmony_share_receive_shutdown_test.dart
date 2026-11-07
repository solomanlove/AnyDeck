import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 排空期间可输出末尾错误；不启动 Core、网络或真实文件收发。
class _Receiver extends Fake implements ShareCoreReceiveSession {
  _Receiver() {
    eventsController.add({'event': 'discovery_ready'});
  }
  final eventsController = StreamController<Map<String, dynamic>>();
  void Function()? whileStopping;
  @override
  Stream<Map<String, dynamic>> get events => eventsController.stream;
  @override
  Future<void> stop() async {
    whileStopping?.call();
    await Future<void>.value();
  }
}

/// 每轮独立 Stream，覆盖自然结束、主动刷新与重新启用。
class _Client extends Fake implements ShareCoreClient {
  final receivers = <_Receiver>[];
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
}

const _failure = {
  'event': 'error',
  'code': 'receive_failed',
  'reason': 'unclassified',
};
const _peer = {
  'event': 'device',
  'ip': '127.0.0.2',
  'port': 44800,
  'name': 'fixture',
};
Future<void> _events() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.value();
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
      await receiver.eventsController.close();
    }
    service.dispose();
  });

  for (final streamError in [false, true]) {
    test('主动刷新排空期间的${streamError ? 'Stream' : 'IPC'}错误不显示为新操作失败', () async {
      await service.start();
      final first = client.receivers.single;
      final failures = <String>[];
      service.addListener(() {
        if (service.error != null) failures.add(service.error!);
      });
      first.whileStopping = () {
        if (streamError) {
          first.eventsController.addError(StateError('receiver closed'));
        } else {
          first.eventsController.add(_failure);
        }
      };
      await service.refresh();
      expect(client.receivers, hasLength(2));
      expect(failures, isEmpty);
      expect(service.error, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(service.scanning, isTrue);
    });
    test('活动接收器的${streamError ? 'Stream' : 'IPC'}错误仍可见', () async {
      await service.start();
      final receiver = client.receivers.single;
      if (streamError) {
        receiver.eventsController.addError(StateError('active receive failed'));
      } else {
        receiver.eventsController.add(_failure);
      }
      await _events();
      expect(
        service.error,
        contains(streamError ? 'active receive failed' : 'receive_failed'),
      );
      expect(service.scanning, isFalse);
    });
  }

  test('自然结束发现窗口后清理旧设备，新窗口重新确认可见性', () async {
    await service.start();
    client.receivers.single.eventsController.add(_peer);
    await _events();
    expect(service.peers, hasLength(1));
    await client.receivers.single.eventsController.close();
    expect(service.peers, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(client.receivers, hasLength(2));
    expect(service.peers, isEmpty);
    client.receivers.last.eventsController.add(_peer);
    await _events();
    expect(service.peers, hasLength(1));
  });
  test('重新启用服务不沿用上次发现窗口的设备', () async {
    await service.start();
    client.receivers.single.eventsController.add(_peer);
    await _events();
    expect(service.peers, hasLength(1));
    await service.stop();
    await service.start();
    expect(client.receivers, hasLength(2));
    expect(service.peers, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(service.scanning, isTrue);
  });
}
