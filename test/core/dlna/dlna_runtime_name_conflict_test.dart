import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/dlna/dlna_protocol.dart';
import 'package:any_deck/core/dlna/dlna_fallback_player.dart';
import 'package:any_deck/core/dlna/dlna_renderer_service.dart';
import 'package:any_deck/core/receiver/receiver_name_probe.dart';
import 'package:any_deck/core/receiver/receiver_names.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('any_deck/dlna_player');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  const firstUuid = 'a7b2c300-0000-4000-8000-000000000001';
  const secondUuid = 'b8c3d400-0000-4000-8000-000000000002';
  const base = 'AnyDeck-MacBook-DLNA';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<DlnaRendererService> start(String uuid) async {
    final service = DlnaRendererService.forTest(uuid: uuid);
    service.setNameConflictHandler((_, _) async {});
    await service.setServerName(base);
    await service.start();
    addTearDown(() async {
      await service.stop();
      service.dispose();
    });
    return service;
  }

  ReceiverSsdpReply advertisement(DlnaRendererService peer, String uuid) =>
      ReceiverSsdpReply(
        sender: InternetAddress.loopbackIPv4,
        message:
            'NOTIFY * HTTP/1.1\r\n'
            'NT: ${DlnaProtocol.deviceType}\r\nNTS: ssdp:alive\r\n'
            'USN: uuid:$uuid::${DlnaProtocol.deviceType}\r\n'
            'LOCATION: http://127.0.0.1:${peer.httpPort}/device.xml\r\n\r\n',
      );

  Future<String> get(DlnaRendererService service) async {
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:${service.httpPort}/device.xml'),
      )).close();
      return await utf8.decoder.bind(response).join();
    } finally {
      client.close(force: true);
    }
  }

  Future<String> soap(
    DlnaRendererService service,
    String action, [
    String args = '',
  ]) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:${service.httpPort}/avtransport/control'),
      );
      request.headers.set(
        'SOAPACTION',
        '"${DlnaProtocol.transportType}#$action"',
      );
      request.add(
        utf8.encode(
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
          '<s:Body><u:$action xmlns:u="${DlnaProtocol.transportType}">$args</u:$action>'
          '</s:Body></s:Envelope>',
        ),
      );
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      return await utf8.decoder.bind(response).join();
    } finally {
      client.close(force: true);
    }
  }

  test('同时启动并漏过启动探测后，通过运行公告收敛到各自稳定短码', () async {
    final services = await Future.wait([start(firstUuid), start(secondUuid)]);
    final first = services[0], second = services[1];
    final ports = services.map((service) => service.httpPort).toList();
    await Future.wait([
      first.observeNameAnnouncement(advertisement(second, secondUuid)),
      second.observeNameAnnouncement(advertisement(first, firstUuid)),
    ]);
    expect(first.serverName, 'AnyDeck-MacBook-A7B2C3-DLNA');
    expect(second.serverName, 'AnyDeck-MacBook-B8C3D4-DLNA');
    expect(services.map((service) => service.httpPort).toList(), ports);
    expect(
      await get(first),
      contains('<friendlyName>${first.serverName}</friendlyName>'),
    );
    expect(
      await get(second),
      contains('<friendlyName>${second.serverName}</friendlyName>'),
    );
    await first.observeNameAnnouncement(advertisement(second, secondUuid));
    expect(first.serverName, 'AnyDeck-MacBook-A7B2C3-DLNA');
  });

  test('后读取对端已改名的描述仍识别同源冲突；相同6位前缀升级至12位', () async {
    const peerUuid = 'a7b2c311-0000-4000-8000-000000000002';
    final first = await start(firstUuid);
    final second = await start(peerUuid);
    await first.observeNameAnnouncement(advertisement(second, peerUuid));
    await second.observeNameAnnouncement(advertisement(first, firstUuid));
    expect(
      first.serverName,
      ReceiverNames.stableFallback(base, 'DLNA', firstUuid, codeLength: 12),
    );
    expect(
      second.serverName,
      ReceiverNames.stableFallback(base, 'DLNA', peerUuid, codeLength: 12),
    );
    expect(first.serverName, isNot(second.serverName));
  });

  test('播放中冲突只改名，HTTP端口、UDN、媒体地址和PLAYING保持不变', () async {
    final first = await start(firstUuid), second = await start(secondUuid);
    final port = first.httpPort;
    await soap(
      first,
      'SetAVTransportURI',
      '<CurrentURI>http://127.0.0.1/media.mp4</CurrentURI>',
    );
    await soap(first, 'Play', '<Speed>1</Speed>');
    calls.clear();
    await first.observeNameAnnouncement(advertisement(second, secondUuid));
    expect(calls, ['setTitle']);
    expect(first.httpPort, port);
    expect(await get(first), contains('<UDN>uuid:$firstUuid</UDN>'));
    expect(
      await soap(first, 'GetMediaInfo'),
      contains('http://127.0.0.1/media.mp4'),
    );
    expect(await soap(first, 'GetTransportInfo'), contains('PLAYING'));
  });

  test('冲突持久化期间用户改名，迟到回调不覆盖新名称', () async {
    final first = await start(firstUuid), second = await start(secondUuid);
    final entered = Completer<void>(), release = Completer<void>();
    first.setNameConflictHandler((_, _) async {
      entered.complete();
      await release.future;
    });
    final observing = first.observeNameAnnouncement(
      advertisement(second, secondUuid),
    );
    await entered.future;
    await first.setServerName('新会议室');
    release.complete();
    await observing;
    expect(first.serverName, '新会议室');
    expect(await get(first), contains('<friendlyName>新会议室</friendlyName>'));
  });

  test('停止后冲突回调完成不改名或重新发布', () async {
    final first = await start(firstUuid), second = await start(secondUuid);
    final entered = Completer<void>(), release = Completer<void>();
    first.setNameConflictHandler((_, _) async {
      entered.complete();
      await release.future;
    });
    final observing = first.observeNameAnnouncement(
      advertisement(second, secondUuid),
    );
    await entered.future;
    await first.stop();
    calls.clear();
    release.complete();
    await observing;
    expect(first.serverName, base);
    expect(first.isRunning, isFalse);
    expect(calls, isEmpty);
  });

  test('回退播放器标题更新失败，实际发现名和UI通知仍完成', () async {
    final fallback = _FailedTitlePlayer();
    final service = DlnaRendererService.forTest(fallback: fallback);
    await service.start();
    addTearDown(service.stop);
    var notifications = 0;
    service.addListener(() => notifications++);
    await service.setServerName('AnyDeck-新会议室-DLNA');
    expect(service.serverName, 'AnyDeck-新会议室-DLNA');
    expect(
      await get(service),
      contains('<friendlyName>AnyDeck-新会议室-DLNA</friendlyName>'),
    );
    expect(notifications, 1);
    expect(fallback.isActive, isTrue);
  });
}

/// 模拟播放器控制通道暂时不可用，标题失败不应影响已在播放的媒体。
class _FailedTitlePlayer extends DlnaFallbackPlayer {
  _FailedTitlePlayer() : super(onStopped: () {}, onFailed: (_) {});
  @override
  bool get hasWindow => true;
  @override
  bool get isActive => true;
  @override
  Future<void> setTitle(String title) async =>
      throw StateError('Unavailable title channel');
  @override
  Future<void> stop() async {}
}
