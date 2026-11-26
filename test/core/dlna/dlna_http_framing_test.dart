import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/dlna/dlna_renderer_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// 使用真实 HTTP 连接检查握手报文，避免客户端自动解 chunked 掩盖兼容问题。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DlnaRendererService service;
  late HttpClient client;
  HttpOverrides? previousOverrides;
  const channel = MethodChannel('any_deck/dlna_player');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getVolume') return 0.5;
      return null;
    });
    service = DlnaRendererService.forTest();
    await service.start();
    await service.setServerName('客厅 & 电脑');
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await service.stop();
    messenger.setMockMethodCallHandler(channel, null);
    HttpOverrides.global = previousOverrides;
  });

  test('设备与三个服务描述使用 UTF-8 Content-Length，不发送 chunked', () async {
    for (final path in [
      '/device.xml',
      '/avtransport.xml',
      '/rendering.xml',
      '/connection.xml',
    ]) {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${service.httpPort}$path'),
      );
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        [],
        (all, data) => all..addAll(data),
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(response.contentLength, bytes.length, reason: path);
      expect(
        response.headers.value(HttpHeaders.transferEncodingHeader),
        isNull,
      );
      expect(response.headers.contentType?.mimeType, 'text/xml');
      if (path == '/device.xml') {
        final xml = utf8.decode(bytes);
        expect(xml, contains('客厅 &amp; 电脑'));
        expect(bytes.length, greaterThan(xml.length));
      }
    }
  });

  for (final (scenario, hostHeader, expectedHost) in [
    ('Host 带正确端口', null, '127.0.0.1'),
    ('Host 省略端口', '127.0.0.1', '127.0.0.1'),
    ('Host 携带其他端口', '127.0.0.1:80', '127.0.0.1'),
    ('Host 使用主机名', 'anydeck.local', 'anydeck.local'),
  ]) {
    test('$scenario，控制地址使用接收服务的实际端口', () async {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${service.httpPort}/device.xml'),
      );
      if (hostHeader != null) {
        request.headers.set(HttpHeaders.hostHeader, hostHeader);
      }
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      final xml = XmlDocument.parse(
        await response.transform(utf8.decoder).join(),
      );
      final base = Uri.parse(xml.findAllElements('URLBase').single.innerText);
      final controlPath = xml.findAllElements('controlURL').first.innerText;
      // 按控制端的用法解析相对 URL，检查最终的 SOAP 目标。
      expect(
        base.resolve(controlPath),
        Uri.parse(
          'http://$expectedHost:${service.httpPort}/avtransport/control',
        ),
      );
    });
  }

  test('订阅后的初始 NOTIFY 使用确定长度并保留事件内容', () async {
    final callback = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final event =
        Completer<({int length, String? encoding, List<int> bytes})>();
    callback.listen((request) async {
      final length = request.contentLength;
      final encoding = request.headers.value(
        HttpHeaders.transferEncodingHeader,
      );
      final bytes = await request.fold<List<int>>(
        [],
        (all, data) => all..addAll(data),
      );
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      if (!event.isCompleted) {
        event.complete((length: length, encoding: encoding, bytes: bytes));
      }
    });
    addTearDown(() => callback.close(force: true));
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
    expect(response.headers.value('SID'), startsWith('uuid:'));
    await response.drain<void>();
    final notification = await event.future.timeout(const Duration(seconds: 3));
    expect(notification.length, notification.bytes.length);
    expect(notification.encoding, isNull);
    final xml = utf8.decode(notification.bytes);
    expect(xml, contains('NO_MEDIA_PRESENT'));
    expect(xml, contains('LastChange'));
  });
}
