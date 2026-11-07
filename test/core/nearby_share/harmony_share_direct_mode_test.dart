import 'dart:async';
import 'dart:io';

import 'package:any_deck/app/settings/harmony_share_preference_keys.dart';
import 'package:any_deck/core/nearby_share/harmony_share_service.dart';
import 'package:any_deck/core/nearby_share/share_core_client.dart';
import 'package:any_deck/core/nearby_share/share_network.dart';
import 'package:any_deck/core/nearby_share/share_transfer_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用内存发现事件验证模式切换，不启动原生 Core 或修改真实 Wi-Fi。
class _Receiver extends Fake implements ShareCoreReceiveSession {
  _Receiver() {
    eventsController.add({'event': 'discovery_ready'});
  }

  final eventsController = StreamController<Map<String, dynamic>>();
  int stops = 0;

  @override
  Stream<Map<String, dynamic>> get events => eventsController.stream;

  @override
  Future<void> stop() async {
    stops++;
    // 停止中的迟到事件不能重新占用收发状态。
    eventsController.add({'event': 'session_started'});
    await Future<void>.delayed(Duration.zero);
  }
}

class _Client extends Fake implements ShareCoreClient {
  _Client({this.directAvailable = true});

  final bool directAvailable;
  final modes = <bool>[];
  final localAddresses = <String>[];
  final receivers = <_Receiver>[];

  Future<ShareCoreReceiveSession> _receive(bool direct, InternetAddress local) async {
    localAddresses.add(local.address);
    modes.add(direct);
    if (direct && !directAvailable) {
      throw const FormatException('Share Core direct mode unavailable');
    }
    final receiver = _Receiver();
    receivers.add(receiver);
    return receiver;
  }

  @override
  Future<ShareCoreReceiveSession> startBatchReceiver({
    required InternetAddress localAddress,
    required InternetAddress broadcastAddress,
    required Directory outputDirectory,
    String localName = 'AnyDeck',
  }) => _receive(false, localAddress);

  @override
  Future<ShareCoreReceiveSession> startDirectBatchReceiver({
    required InternetAddress localAddress,
    required InternetAddress broadcastAddress,
    required Directory outputDirectory,
    String localName = 'AnyDeck',
  }) => _receive(true, localAddress);
}

/// 每例只注入网络地址和接收器，模式持久化仍走实际 resolver。
HarmonyShareService _service(_Client client, {bool usePreferences = true, Future<ShareNetwork> Function()? detectNetwork}) =>
    HarmonyShareService.testing(
      client: client,
      nativeBatch: true,
      downloads: () async => Directory.systemTemp,
      resolveDirectMode: usePreferences ? ShareTransferMode.resolve : null,
      detectNetwork: detectNetwork ?? () async => ShareNetwork(
        InternetAddress('192.168.1.2'),
        InternetAddress('192.168.1.255'),
      ),
    );

Future<void> _close(HarmonyShareService service, _Client client) async {
  await service.stop();
  service.dispose();
  for (final receiver in client.receivers) {
    await receiver.eventsController.close();
  }
}

void main() {
  test('直连允许尚无LAN地址，默认LAN与其他检测错误仍明确失败', () async {
    for (final direct in [false, true]) {
      SharedPreferences.setMockInitialValues({HarmonySharePreferenceKeys.directMode: direct});
      final client = _Client();
      final service = _service(client, detectNetwork: () async => throw const FileSystemException('No active IPv4 network with netmask'));
      await service.start();
      if (direct) {
        expect(client.modes, [true]);
        expect(client.localAddresses, ['0.0.0.0']);
        expect(service.error, isNull);
      } else {
        expect(client.modes, isEmpty);
        expect(service.error, contains('No active IPv4 network with netmask'));
      }
      await _close(service, client);
    }
    SharedPreferences.setMockInitialValues({HarmonySharePreferenceKeys.directMode: true});
    final client = _Client();
    final service = _service(client, detectNetwork: () async => throw const FileSystemException('network inspection failed'));
    await service.start();
    expect(client.modes, isEmpty);
    expect(service.error, contains('network inspection failed'));
    await _close(service, client);
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('无配置默认 LAN，testing 旧调用无需新增 resolver', () async {
    expect(await ShareTransferMode.resolve(), isFalse);
    final client = _Client();
    final service = _service(client, usePreferences: false);
    try {
      await service.start();
      await Future<void>.delayed(Duration.zero);
      expect(client.modes, [false]);
      expect(service.directModeEnabled, isFalse);
      expect(service.scanning, isTrue);
    } finally {
      await _close(service, client);
    }
  });

  test('开关成功后重启接收器，每轮刷新从持久化配置重新读取', () async {
    final prefs = await SharedPreferences.getInstance();
    final client = _Client();
    final service = _service(client);
    try {
      await service.start();
      await service.configureDirectMode(true, () async {
        await prefs.setBool(HarmonySharePreferenceKeys.directMode, true);
      });
      await Future<void>.delayed(Duration.zero);
      expect(client.modes, [false, true]);
      expect(client.receivers.first.stops, 1);
      expect(service.directModeEnabled, isTrue);
      expect(service.scanning, isTrue);
      await prefs.setBool(HarmonySharePreferenceKeys.directMode, false);
      await service.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(client.modes, [false, true, false]);
      expect(client.receivers[1].stops, 1);
      expect(service.directModeEnabled, isFalse);
      expect(service.scanning, isTrue);
    } finally {
      await _close(service, client);
    }
  });

  for (final initial in [false, true]) {
    for (final fail in [false, true]) {
      test('模式 $initial 切换${fail ? "保存失败恢复旧模式" : "成功"}，保存期间收发互斥', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(HarmonySharePreferenceKeys.directMode, initial);
        final client = _Client();
        final service = _service(client);
        final entered = Completer<void>();
        final writing = Completer<void>();
        try {
          await service.start();
          final operation = service.configureDirectMode(!initial, () async {
            entered.complete();
            await writing.future;
            if (fail) throw StateError('Synthetic write failure');
            await prefs.setBool(
              HarmonySharePreferenceKeys.directMode,
              !initial,
            );
          });
          final result = fail
              ? expectLater(operation, throwsStateError)
              : operation;
          await entered.future;
          expect(service.configuring, isTrue);
          expect(service.scanning, isFalse);
          expect(service.canSelectFiles, isFalse);
          expect(service.busy, isFalse);
          expect(service.directModeEnabled, initial);
          expect(client.receivers.single.stops, 1);
          var concurrentWrites = 0;
          Future<void> concurrentSave() async => concurrentWrites++;
          await expectLater(
            service.configureDirectMode(initial, concurrentSave),
            throwsStateError,
          );
          await expectLater(
            service.configureLocalName('并发名称', concurrentSave),
            throwsStateError,
          );
          await expectLater(
            service.sendFiles(
              ShareCorePeer(
                address: InternetAddress('192.168.1.3'),
                port: 44800,
                name: 'Synthetic peer',
              ),
              [],
            ),
            throwsStateError,
          );
          expect(concurrentWrites, 0);
          writing.complete();
          await result;
          await Future<void>.delayed(Duration.zero);
          final expected = fail ? initial : !initial;
          expect(client.modes, [initial, expected]);
          expect(service.directModeEnabled, expected);
          expect(await ShareTransferMode.resolve(), expected);
          expect(service.configuring, isFalse);
          expect(service.scanning, isTrue);
          expect(service.busy, isFalse);
        } finally {
          if (!writing.isCompleted) writing.complete();
          await _close(service, client);
        }
      });
    }
  }

  test('接收传输忙碌时拒绝切换，保留现有会话且不保存', () async {
    final client = _Client();
    final service = _service(client);
    var writes = 0;
    try {
      await service.start();
      client.receivers.single.eventsController.add({
        'event': 'session_started',
      });
      await Future<void>.delayed(Duration.zero);
      expect(service.busy, isTrue);
      expect(service.receiving, isTrue);
      await expectLater(
        service.configureDirectMode(true, () async => writes++),
        throwsStateError,
      );
      expect(writes, 0);
      expect(client.receivers.single.stops, 0);
      expect(client.modes, [false]);
      expect(service.configuring, isFalse);
    } finally {
      await _close(service, client);
    }
  });

  test('服务关闭时只保存模式，重新启用才启动直连接收器', () async {
    final prefs = await SharedPreferences.getInstance();
    final client = _Client();
    final service = _service(client);
    try {
      await service.configureDirectMode(true, () async {
        await prefs.setBool(HarmonySharePreferenceKeys.directMode, true);
      });
      expect(service.enabled, isFalse);
      expect(service.directModeEnabled, isTrue);
      expect(service.scanning, isFalse);
      expect(client.modes, isEmpty);
      await service.start();
      expect(client.modes, [true]);
    } finally {
      await _close(service, client);
    }
  });

  test('切换保存期间关闭服务，保存完成后不重启接收器', () async {
    final prefs = await SharedPreferences.getInstance();
    final client = _Client();
    final service = _service(client);
    final entered = Completer<void>();
    final writing = Completer<void>();
    try {
      await service.start();
      final operation = service.configureDirectMode(true, () async {
        entered.complete();
        await writing.future;
        await prefs.setBool(HarmonySharePreferenceKeys.directMode, true);
      });
      await entered.future;
      await service.stop();
      writing.complete();
      await operation;
      expect(service.enabled, isFalse);
      expect(service.configuring, isFalse);
      expect(client.modes, [false]);
      expect(client.receivers.single.stops, 1);
      await service.start();
      expect(client.modes, [false, true]);
    } finally {
      if (!writing.isCompleted) writing.complete();
      await _close(service, client);
    }
  });

  test('旧 Core 不支持直连时明确失败，手动关闭开关后恢复 LAN', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(HarmonySharePreferenceKeys.directMode, true);
    final client = _Client(directAvailable: false);
    final service = _service(client);
    try {
      await service.start();
      expect(client.modes, [true]);
      expect(service.error, contains('direct mode unavailable'));
      expect(service.scanning, isFalse);
      expect(service.startingDiscovery, isFalse);
      await service.configureDirectMode(false, () async {
        await prefs.setBool(HarmonySharePreferenceKeys.directMode, false);
      });
      await Future<void>.delayed(Duration.zero);
      expect(client.modes, [true, false]);
      expect(service.error, isNull);
      expect(service.directModeEnabled, isFalse);
      expect(service.scanning, isTrue);
    } finally {
      await _close(service, client);
    }
  });
}
