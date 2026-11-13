import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/dlna/dlna_renderer_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实 HTTP 请求验证同名电脑不会共用 UDN 或订阅身份；不发布 LAN 广播。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const firstUuid = '6b1c354a-f3e0-4ed4-a917-d55300000001';
  const secondUuid = '6b1c354a-f3e0-4ed4-a917-d55300000002';
  const channel = MethodChannel('any_deck/dlna_player');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final services = <DlnaRendererService>[];
  late HttpClient client;
  HttpOverrides? previousOverrides;

  setUp(() {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    for (final service in services) {
      await service.stop();
    }
    services.clear();
    messenger.setMockMethodCallHandler(channel, null);
    HttpOverrides.global = previousOverrides;
  });

  Future<DlnaRendererService> start(String uuid) async {
    final service = DlnaRendererService.forTest(uuid: uuid);
    services.add(service);
    await service.start();
    await service.setServerName('AnyDeck-办公室Mac-DLNA');
    return service;
  }

  Future<String> description(DlnaRendererService service) async {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${service.httpPort}/device.xml'),
    );
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    return response.transform(utf8.decoder).join();
  }

  Future<String?> subscribe(
    DlnaRendererService service,
    HttpServer callback,
  ) async {
    final request = await client.openUrl(
      'SUBSCRIBE',
      Uri.parse('http://127.0.0.1:${service.httpPort}/avtransport/event'),
    );
    request.headers.set(
      'CALLBACK',
      '<http://127.0.0.1:${callback.port}/event>',
    );
    request.headers.set('NT', 'upnp:event');
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    final sid = response.headers.value('SID');
    await response.drain<void>();
    return sid;
  }

  test('同名接收端的 HTTP 描述保留各自 UDN，改名和重启不改变身份', () async {
    final first = await start(firstUuid);
    final second = await start(secondUuid);
    final firstXml = await description(first);
    final secondXml = await description(second);
    expect(firstXml, contains('<UDN>uuid:$firstUuid</UDN>'));
    expect(secondXml, contains('<UDN>uuid:$secondUuid</UDN>'));
    expect(firstXml, isNot(contains(secondUuid)));
    expect(secondXml, isNot(contains(firstUuid)));
    expect(
      firstXml,
      contains('<friendlyName>${first.serverName}</friendlyName>'),
    );
    expect(
      secondXml,
      contains('<friendlyName>${first.serverName}</friendlyName>'),
    );

    await first.setServerName('AnyDeck-会议室-DLNA');
    expect(await description(first), contains('<UDN>uuid:$firstUuid</UDN>'));
    await first.stop();
    final restarted = await start(firstUuid);
    expect(
      await description(restarted),
      contains('<UDN>uuid:$firstUuid</UDN>'),
    );
    expect(await description(second), contains('<UDN>uuid:$secondUuid</UDN>'));
  });

  test('两个接收端的首个事件订阅 SID 也不会互相混淆', () async {
    final first = await start(firstUuid);
    final second = await start(secondUuid);
    final callback = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    callback.listen((request) async {
      await request.drain<void>();
      await request.response.close();
    });
    addTearDown(() => callback.close(force: true));
    final firstSid = await subscribe(first, callback);
    final secondSid = await subscribe(second, callback);
    expect(firstSid, startsWith('uuid:$firstUuid-'));
    expect(secondSid, startsWith('uuid:$secondUuid-'));
    expect(firstSid, isNot(secondSid));
  });
}
