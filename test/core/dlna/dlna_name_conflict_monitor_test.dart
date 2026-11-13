import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/dlna/dlna_name_conflict_monitor.dart';
import 'package:any_deck/core/dlna/dlna_protocol.dart';
import 'package:any_deck/core/dlna/dlna_renderer_service.dart';
import 'package:any_deck/core/receiver/receiver_name_probe.dart';
import 'package:any_deck/core/receiver/receiver_names.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _uuidA = '11111111-1111-4111-8111-111111111111';
const _uuidB = '22222222-2222-4222-8222-222222222222';
const _base = 'AnyDeck-办公室 Mac-DLNA';

/// fake SSDP 消息控制并发顺序；设备描述仍可经真实临时 HTTP 服务读取。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('any_deck/dlna_player');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final monitors = <DlnaNameConflictMonitor>[];
  final services = <DlnaRendererService>[];
  late HttpClient client;
  HttpOverrides? previousOverrides;

  setUp(() {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    client = HttpClient();
    messenger.setMockMethodCallHandler(channel, (_) async => null);
  });

  tearDown(() async {
    for (final monitor in monitors) {
      monitor.dispose();
    }
    await Future.wait(monitors.map((monitor) => monitor.idle));
    monitors.clear();
    client.close(force: true);
    for (final service in services) {
      await service.stop();
    }
    services.clear();
    messenger.setMockMethodCallHandler(channel, null);
    HttpOverrides.global = previousOverrides;
  });

  String xml(String name) =>
      '<root><device><deviceType>${DlnaProtocol.deviceType}'
      '</deviceType><friendlyName>${DlnaProtocol.escape(name)}</friendlyName>'
      '</device></root>';

  ReceiverSsdpReply packet({
    String uuid = _uuidB,
    String location = 'http://127.0.0.1:18583/device.xml',
    String? notification,
  }) => ReceiverSsdpReply(
    sender: InternetAddress.loopbackIPv4,
    message: notification == null
        ? 'HTTP/1.1 200 OK\r\nST: ${DlnaProtocol.deviceType}\r\n'
              'USN: uuid:$uuid::${DlnaProtocol.deviceType}\r\nLOCATION: $location\r\n\r\n'
        : 'NOTIFY * HTTP/1.1\r\nNT: ${DlnaProtocol.deviceType}\r\n'
              'NTS: ssdp:$notification\r\nUSN: uuid:$uuid::${DlnaProtocol.deviceType}\r\n'
              'LOCATION: $location\r\n\r\n',
  );

  DlnaNameConflictMonitor monitor({
    String uuid = _uuidA,
    String base = _base,
    required String Function() current,
    required Future<void> Function(String, String) changed,
    ReceiverDescriptionReader? reader,
    Duration timeout = const Duration(seconds: 1),
    Duration ttl = const Duration(seconds: 30),
  }) {
    final value = DlnaNameConflictMonitor(
      uuid: uuid,
      baseName: base,
      currentName: current,
      onConflict: changed,
      descriptionReader: reader,
      requestTimeout: timeout,
      cacheTtl: ttl,
    );
    monitors.add(value);
    return value;
  }

  Future<String> read(Uri location) async {
    final request = await client.getUrl(location);
    final response = await request.close();
    return response.transform(utf8.decoder).join();
  }

  Future<DlnaRendererService> service(String uuid) async {
    final value = DlnaRendererService.forTest(uuid: uuid);
    services.add(value);
    await value.setServerName(_base);
    await value.start();
    return value;
  }

  test('先改名的对端仍可被识别，两个同时启动的实例均收敛到稳定名称', () async {
    final first = await service(_uuidA);
    final second = await service(_uuidB);
    final firstRenamed = Completer<void>();
    final firstLocation = Uri.parse(
      'http://127.0.0.1:${first.httpPort}/device.xml',
    );
    final secondLocation = Uri.parse(
      'http://127.0.0.1:${second.httpPort}/device.xml',
    );
    var changesA = 0;
    var changesB = 0;
    final firstMonitor = monitor(
      current: () => first.serverName,
      changed: (expected, proposed) async {
        expect(expected, _base);
        changesA++;
        await first.setServerName(proposed);
        firstRenamed.complete();
      },
    );
    final secondMonitor = monitor(
      uuid: _uuidB,
      current: () => second.serverName,
      reader: (location, _) async {
        await firstRenamed.future;
        return read(location);
      },
      changed: (expected, proposed) async {
        expect(expected, _base);
        changesB++;
        await second.setServerName(proposed);
      },
    );
    // 两边同时收到发现消息，但 B 被刻意延后到 A 已更新 device.xml 后才读取。
    firstMonitor.observe(packet(uuid: _uuidB, location: '$secondLocation'));
    secondMonitor.observe(
      packet(uuid: _uuidA, location: '$firstLocation', notification: 'alive'),
    );
    await Future.wait([firstMonitor.idle, secondMonitor.idle]);
    expect(first.serverName, 'AnyDeck-办公室 Mac-111111-DLNA');
    expect(second.serverName, 'AnyDeck-办公室 Mac-222222-DLNA');
    expect(first.serverName, isNot(second.serverName));
    expect(
      ReceiverNameProbe.friendlyName(await read(firstLocation)),
      first.serverName,
    );
    expect(
      ReceiverNameProbe.friendlyName(await read(secondLocation)),
      second.serverName,
    );
    expect(await read(firstLocation), contains('<UDN>uuid:$_uuidA</UDN>'));
    for (var index = 0; index < 10; index++) {
      firstMonitor.observe(
        packet(
          uuid: _uuidB,
          location: '$secondLocation',
          notification: 'update',
        ),
      );
      secondMonitor.observe(packet(uuid: _uuidA, location: '$firstLocation'));
    }
    await Future.wait([firstMonitor.idle, secondMonitor.idle]);
    expect(changesA, 1);
    expect(changesB, 1);
  });

  test('稳定短码发生前缀碰撞时有限升级到12或32位，已升级名称不降级', () async {
    for (final pair in [
      (
        'abcdef12-3456-4000-8000-000000000001',
        'abcdef65-4321-4000-8000-000000000002',
        12,
      ),
      (
        '6b1c354a-f3e0-4ed4-a917-d55300000001',
        '6b1c354a-f3e0-4ed4-a917-d55300000002',
        32,
      ),
    ]) {
      var current = ReceiverNames.disambiguate(
        _base,
        'DLNA',
        pair.$1.replaceAll('-', '').substring(0, 6).toUpperCase(),
      );
      final ownCode = pair.$1.replaceAll('-', '').toUpperCase();
      final peerCode = pair.$2.replaceAll('-', '').toUpperCase();
      var peerPublished = ReceiverNames.disambiguate(
        _base,
        'DLNA',
        peerCode.substring(0, 6),
      );
      final value = monitor(
        uuid: pair.$1,
        current: () => current,
        reader: (_, _) async => xml(peerPublished),
        changed: (_, proposed) async => current = proposed,
        ttl: Duration.zero,
      );
      value.observe(packet(uuid: pair.$2));
      await value.idle;
      expect(
        current,
        ReceiverNames.disambiguate(
          _base,
          'DLNA',
          ownCode.substring(0, pair.$3),
        ),
      );
      final peerMonitor = monitor(
        uuid: pair.$2,
        current: () => peerPublished,
        reader: (_, _) async => xml(current),
        changed: (_, proposed) async => peerPublished = proposed,
      );
      peerMonitor.observe(packet(uuid: pair.$1));
      await peerMonitor.idle;
      expect(
        peerPublished,
        ReceiverNames.stableFallback(
          _base,
          'DLNA',
          pair.$2,
          codeLength: pair.$3,
        ),
      );
      expect(peerPublished, isNot(current));
      final upgraded = current;
      peerPublished = _base;
      value.observe(packet(uuid: _uuidB));
      await value.idle;
      expect(current, upgraded);
    }
  });

  test('实际名称改变后同一对端可立即复查，仍不重复追加短码', () async {
    var current = _base;
    var reads = 0;
    var changes = 0;
    final value = monitor(
      current: () => current,
      reader: (_, _) async {
        reads++;
        return xml(_base);
      },
      changed: (_, proposed) async {
        changes++;
        current = proposed;
      },
    );
    value.observe(packet());
    await value.idle;
    value.observe(packet(notification: 'update'));
    await value.idle;
    expect(reads, 2);
    expect(changes, 1);
    expect(current, 'AnyDeck-办公室 Mac-111111-DLNA');
  });

  test('只查询可信设备，NOTIFY与HTTP重复报文共用缓存', () async {
    var reads = 0;
    var changes = 0;
    final value = monitor(
      current: () => _base,
      changed: (_, _) async => changes++,
      reader: (_, _) async {
        reads++;
        return xml('其他设备');
      },
    );
    value.observe(packet(uuid: _uuidA));
    value.observe(packet(notification: 'byebye'));
    value.observe(packet(location: 'http://example.com/device.xml'));
    value.observe(packet(location: 'http://127.0.0.2/device.xml'));
    value.observe(packet(notification: 'alive'));
    value.observe(packet(notification: 'update'));
    value.observe(packet());
    await value.idle;
    expect(reads, 1);
    expect(changes, 0);
  });

  test('设备队列和HTTP读取严格有界，最多32项和2个并发', () async {
    var reads = 0;
    var active = 0;
    var maximum = 0;
    final value = monitor(
      current: () => _base,
      changed: (_, _) async {},
      reader: (_, _) async {
        reads++;
        active++;
        if (active > maximum) maximum = active;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        active--;
        return xml('其他设备');
      },
    );
    for (var index = 0; index < 100; index++) {
      value.observe(
        packet(location: 'http://127.0.0.1:18583/device$index.xml'),
      );
    }
    await value.idle;
    expect(reads, 32);
    expect(maximum, 2);
  });

  test('用户改名与dispose使迟到的描述失效，清空旧队列', () async {
    for (final stopped in [false, true]) {
      final response = Completer<String?>();
      var changes = 0;
      final value = monitor(
        current: () => _base,
        changed: (_, _) async => changes++,
        reader: (_, _) => response.future,
      );
      value.observe(packet());
      if (stopped) {
        value.dispose();
      } else {
        value.updateName('新名称');
      }
      response.complete(xml(_base));
      await value.idle;
      expect(changes, 0);
    }
  });

  test('原始名未更新但实际广播名已被用户改变时，旧查询也不可覆盖', () async {
    final response = Completer<String?>();
    var current = _base;
    var changes = 0;
    final value = monitor(
      current: () => current,
      changed: (_, _) async => changes++,
      reader: (_, _) => response.future,
    );
    value.observe(packet());
    current = '用户新名称';
    response.complete(xml(_base));
    await value.idle;
    expect(changes, 0);
  });

  test('描述超时、超限、畸形XML和回调失败均不会向外抛出', () async {
    for (final reader in <ReceiverDescriptionReader>[
      (_, _) => Completer<String?>().future,
      (_, _) async => 'a' * (64 * 1024 + 1),
      (_, _) async => '<root>',
      (_, _) async => throw const SocketException('设备离线'),
      (_, _) async => xml(_base),
    ]) {
      final value = monitor(
        current: () => _base,
        reader: reader,
        timeout: const Duration(milliseconds: 20),
        changed: (_, _) async => throw StateError('持久化失败'),
      );
      value.observe(packet());
      await value.idle.timeout(const Duration(seconds: 1));
    }
  });

  test('停止监视器立即关闭实际HTTP连接且不会应用返回的名称', () async {
    final received = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      if (!received.isCompleted) received.complete();
      // 故意不结束响应，由监视器停止动作关闭客户端连接。
    });
    var changes = 0;
    final value = monitor(
      current: () => _base,
      changed: (_, _) async => changes++,
      timeout: const Duration(milliseconds: 100),
    );
    value.observe(
      packet(location: 'http://127.0.0.1:${server.port}/device.xml'),
    );
    await received.future.timeout(const Duration(seconds: 1));
    value.dispose();
    await value.idle.timeout(const Duration(seconds: 1));
    expect(changes, 0);
  });
}
