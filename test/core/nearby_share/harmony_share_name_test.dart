import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 只观察通用 IPC 边界，不启动真实 Core、蓝牙或网络。
class _Receiver extends Fake implements ShareCoreReceiveSession {
  final stream = StreamController<Map<String, dynamic>>();
  int stops = 0;
  @override
  Stream<Map<String, dynamic>> get events => stream.stream;
  @override
  Future<void> stop() async {
    stops++;
    // 模拟停止过程中迟到的状态，不允许它穿过配置预留边界。
    stream.add({'event': 'session_started'});
    await Future<void>.delayed(Duration.zero);
  }
}

class _Transfer extends Fake implements ShareBatchTransfer {
  @override
  Stream<ShareCoreProgress> get progress => const Stream.empty();
  @override
  Future<Map<String, dynamic>> get result async => {};
}

class _Client extends Fake implements ShareCoreClient {
  final receivers = <_Receiver>[];
  final names = <String>[];
  ShareBatchRequest? sent;
  @override
  Future<ShareCoreReceiveSession> startBatchReceiver({
    required InternetAddress localAddress,
    required InternetAddress broadcastAddress,
    required Directory outputDirectory,
    String localName = 'AnyDeck',
  }) async {
    names.add(localName);
    final receiver = _Receiver();
    receivers.add(receiver);
    return receiver;
  }

  @override
  Future<ShareBatchTransfer> sendBatchForTest({
    required InternetAddress localAddress,
    required ShareCorePeer peer,
    required ShareBatchRequest request,
  }) async {
    sent = request;
    return _Transfer();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final fail in [false, true]) {
    test('名称${fail ? "保存失败恢复旧值" : "保存成功用于双向新会话"}，写入期间收发互斥', () async {
      final root = await Directory.systemTemp.createTemp('share-name-');
      final client = _Client();
      var saved = '初始 Mac';
      final service = HarmonyShareService.testing(
        client: client,
        nativeBatch: true,
        downloads: () async => root,
        resolveLocalName: () async => saved,
        detectNetwork: () async => ShareNetwork(
          InternetAddress('192.168.1.2'),
          InternetAddress('192.168.1.255'),
        ),
      );
      final entered = Completer<void>();
      final writing = Completer<void>();
      try {
        await service.start();
        expect(client.names, ['初始 Mac']);
        final operation = service.configureLocalName('新名称', () async {
          entered.complete();
          await writing.future;
          if (fail) throw StateError('Synthetic write failure');
          saved = '新名称';
        });
        // 先注册错误处理，避免模拟写入失败变成未处理 Future。
        final result = fail
            ? expectLater(operation, throwsStateError)
            : operation;
        await entered.future;
        expect(service.configuring, isTrue);
        expect(service.busy, isFalse);
        expect(service.canSelectFiles, isFalse);
        expect(service.localName, '初始 Mac');
        final peer = ShareCorePeer(
          address: InternetAddress('192.168.1.3'),
          port: 44800,
          name: 'Synthetic peer',
        );
        await expectLater(service.sendFiles(peer, []), throwsStateError);
        await expectLater(
          service.configureLocalName('并发写入', () async {}),
          throwsStateError,
        );
        writing.complete();
        await result;
        final expected = fail ? '初始 Mac' : '新名称';
        expect(service.configuring, isFalse);
        expect(service.localName, expected);
        expect(client.names, ['初始 Mac', expected]);
        final file = await File('${root.path}/tiny.bin').writeAsBytes([1, 2]);
        await service.send(peer, file);
        expect(client.sent!.localName, expected);
        expect(client.names.last, expected);
      } finally {
        await service.stop();
        service.dispose();
        for (final receiver in client.receivers) {
          await receiver.stream.close();
        }
        await root.delete(recursive: true);
      }
    });
  }

  test('忙碌或非法名称不会停止会话或写入设置', () async {
    final client = _Client();
    final service = HarmonyShareService.testing(
      client: client,
      nativeBatch: true,
      downloads: () async => Directory.systemTemp,
      detectNetwork: () async => ShareNetwork(
        InternetAddress('192.168.1.2'),
        InternetAddress('192.168.1.255'),
      ),
    );
    var writes = 0;
    try {
      await service.start();
      service.busy = true;
      await expectLater(
        service.configureLocalName('Mac', () async {
          writes++;
        }),
        throwsStateError,
      );
      service.busy = false;
      await expectLater(
        service.configureLocalName('bad\n', () async {
          writes++;
        }),
        throwsFormatException,
      );
      expect(writes, 0);
      expect(client.receivers.single.stops, 0);
    } finally {
      await service.stop();
      service.dispose();
      for (final receiver in client.receivers) {
        await receiver.stream.close();
      }
    }
  });
}
