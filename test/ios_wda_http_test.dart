import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/ios/ios_wda_http.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late IosWdaHttp client;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = IosWdaHttp(
      server.port,
      timeout: const Duration(milliseconds: 200),
    );
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  test('HTTP and W3C errors must not be accepted as success', () async {
    var count = 0;
    server.listen((request) async {
      count++;
      request.response.statusCode = count == 1 ? 404 : 200;
      request.response.write(
        jsonEncode({
          'value': {'error': 'unknown command', 'message': 'missing session'},
        }),
      );
      await request.response.close();
    });
    await expectLater(client.request('/wda/keys'), throwsStateError);
    await expectLater(client.request('/status'), throwsStateError);
  });

  test(
    'W3C session, point coordinates, and whole swipe use the same endpoint',
    () async {
      final requests = <Map<String, dynamic>>[];
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        if (body.isNotEmpty) {
          requests.add({'path': request.uri.path, 'body': jsonDecode(body)});
        }
        request.response.write(
          jsonEncode({
            'value': request.uri.path == '/session'
                ? {'sessionId': 'session-A', 'capabilities': {}}
                : null,
          }),
        );
        await request.response.close();
      });
      await client.createSession();
      await client.gesture(100, 120, toX: 100, toY: 500, durationMs: 600);
      expect(requests.last['path'], '/session/session-A/actions');
      final actions = requests.last['body']['actions'][0]['actions'] as List;
      expect(actions.map((e) => e['type']), [
        'pointerMove',
        'pointerDown',
        'pause',
        'pointerMove',
        'pointerUp',
      ]);
      expect(actions[3]['duration'], 600);
      expect(actions[3]['y'], 500);
      await expectLater(client.gesture(double.nan, 1), throwsArgumentError);
    },
  );

  test('JSONWP session id and chunked response are decoded', () async {
    server.listen((request) async {
      request.response.headers.chunkedTransferEncoding = true;
      request.response.write('{"sessionId":"legacy",');
      await request.response.flush();
      request.response.write('"status":0,"value":{}}');
      await request.response.close();
    });
    await client.createSession();
    expect(client.path('/source'), '/session/legacy/source');
  });

  test(
    'nonresponsive WDA times out without blocking the Dart event loop',
    () async {
      server.listen((_) {});
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 10),
        (_) => ticks++,
      );
      try {
        await expectLater(
          client.request('/status'),
          throwsA(isA<TimeoutException>()),
        );
        expect(ticks, greaterThan(3));
      } finally {
        timer.cancel();
      }
    },
  );
}
