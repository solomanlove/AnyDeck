import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/dlna/dlna_protocol.dart';
import 'package:any_deck/core/dlna/dlna_renderer_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SOAP 播放控制、音量和静音状态能正确传给原生播放器', () async {
    final previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousHttpOverrides);
    const channel = MethodChannel('any_deck/dlna_player');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    var volume = 1.0;
    var muted = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'setVolume':
          volume = call.arguments as double;
        case 'getVolume':
          return volume;
        case 'setMute':
          muted = call.arguments as bool;
        case 'getMute':
          return muted;
        case 'position':
        case 'duration':
          return 0.0;
      }
      return null;
    });
    final service = DlnaRendererService.instance;
    await service.start();
    addTearDown(() async {
      await service.stop();
      messenger.setMockMethodCallHandler(channel, null);
    });

    await service.setServerName('客厅 & 电脑');
    expect(service.isRunning, isTrue);
    final descriptionClient = HttpClient();
    final description = await utf8.decoder
        .bind(
          await descriptionClient
              .getUrl(Uri.parse('http://127.0.0.1:18583/device.xml'))
              .then((request) => request.close()),
        )
        .join();
    descriptionClient.close(force: true);
    expect(description, contains('<friendlyName>客厅 &amp; 电脑</friendlyName>'));

    Future<String> send(
      String action,
      String arguments, {
      bool rendering = false,
    }) async {
      final path = rendering ? 'rendering' : 'avtransport';
      final type = rendering
          ? DlnaProtocol.renderingType
          : DlnaProtocol.transportType;
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:18583/$path/control'),
        );
        request.headers.set('SOAPACTION', '"$type#$action"');
        request.write(
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
          '<s:Body><u:$action xmlns:u="$type">$arguments</u:$action>'
          '</s:Body></s:Envelope>',
        );
        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok, reason: action);
        return await utf8.decoder.bind(response).join();
      } finally {
        client.close(force: true);
      }
    }

    await send(
      'SetAVTransportURI',
      '<CurrentURI>http://127.0.0.1/media.mp4</CurrentURI>',
    );
    await send('Play', '<Speed>1</Speed>');
    expect(calls, contains('playUrl'));
    await send('Pause', '');
    expect(
      (await send('GetTransportInfo', '')).contains('PAUSED_PLAYBACK'),
      isTrue,
    );
    await send('Seek', '<Unit>REL_TIME</Unit><Target>00:00:12</Target>');
    expect(calls, contains('seek'));
    await send('Play', '<Speed>1</Speed>');
    expect(calls, contains('play'));

    await send(
      'SetVolume',
      '<DesiredVolume>35</DesiredVolume>',
      rendering: true,
    );
    expect(volume, 0.35);
    await send('SetMute', '<DesiredMute>1</DesiredMute>', rendering: true);
    expect(muted, isTrue);
    expect(
      (await send(
        'GetMute',
        '',
        rendering: true,
      )).contains('<CurrentMute>1</CurrentMute>'),
      isTrue,
    );
    expect(
      (await send(
        'GetVolume',
        '',
        rendering: true,
      )).contains('<CurrentVolume>35</CurrentVolume>'),
      isTrue,
    );
    await send('SetMute', '<DesiredMute>0</DesiredMute>', rendering: true);
    expect(muted, isFalse);
    expect(volume, 0.35);

    await send('Stop', '');
    expect((await send('GetTransportInfo', '')).contains('STOPPED'), isTrue);
    expect(calls, contains('stop'));
  });
}
