import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/dlna/dlna_protocol.dart';
import 'package:any_deck/core/dlna/dlna_fallback_player.dart';
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
    final playedUrls = <String>[];
    var volume = 1.0;
    var muted = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'playUrl':
          playedUrls.add((call.arguments as Map)['url'] as String);
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
    final fallback = _RecordingFallbackPlayer();
    final service = DlnaRendererService.forTest(
      fallback: fallback,
      stopWindowDelay: const Duration(milliseconds: 500),
    );
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
              .getUrl(
                Uri.parse('http://127.0.0.1:${service.httpPort}/device.xml'),
              )
              .then((request) => request.close()),
        )
        .join();
    descriptionClient.close(force: true);
    expect(description, contains('<friendlyName>客厅 &amp; 电脑</friendlyName>'));

    Future<String> send(
      String action,
      String arguments, {
      bool rendering = false,
      bool connection = false,
      String? userAgent,
    }) async {
      final path = connection
          ? 'connection'
          : rendering
          ? 'rendering'
          : 'avtransport';
      final type = connection
          ? DlnaProtocol.connectionType
          : rendering
          ? DlnaProtocol.renderingType
          : DlnaProtocol.transportType;
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse('http://127.0.0.1:${service.httpPort}/$path/control'),
        );
        request.headers.set('SOAPACTION', '"$type#$action"');
        if (userAgent != null) {
          request.headers.set(HttpHeaders.userAgentHeader, userAgent);
        }
        request.add(
          utf8.encode(
            '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
            '<s:Body><u:$action xmlns:u="$type">$arguments</u:$action>'
            '</s:Body></s:Envelope>',
          ),
        );
        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok, reason: action);
        expect(response.headers.contentLength, greaterThan(0), reason: action);
        expect(
          response.headers.value(HttpHeaders.transferEncodingHeader),
          isNull,
          reason: action,
        );
        return await utf8.decoder.bind(response).join();
      } finally {
        client.close(force: true);
      }
    }

    await send(
      'SetAVTransportURI',
      '<CurrentURI>http://127.0.0.1/media.mp4</CurrentURI>'
          '<CurrentURIMetaData>&lt;item&gt;测试 &amp; 视频&lt;/item&gt;</CurrentURIMetaData>',
    );
    expect(
      await send('GetMediaInfo', ''),
      contains(
        '<CurrentURIMetaData>&lt;item&gt;测试 &amp; 视频&lt;/item&gt;</CurrentURIMetaData>',
      ),
    );
    expect(
      await send('GetPositionInfo', ''),
      contains(
        '<TrackMetaData>&lt;item&gt;测试 &amp; 视频&lt;/item&gt;</TrackMetaData>',
      ),
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
    expect(calls, contains('prepare'));
    expect(calls, isNot(contains('close')));

    // 手机可能在旧窗口清理期间立即下发 Play；应使用刚设置的新地址。
    fallback.stopGate = Completer<void>();
    fallback.stopEntered = Completer<void>();
    final switchToB = send(
      'SetAVTransportURI',
      '<CurrentURI>http://127.0.0.1/video-b.mp4</CurrentURI>',
    );
    await fallback.stopEntered!.future;
    final playB = send('Play', '<Speed>1</Speed>');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(playedUrls.last, 'http://127.0.0.1/media.mp4');
    fallback.stopGate!.complete();
    await Future.wait([switchToB, playB]);
    expect(playedUrls.last, 'http://127.0.0.1/video-b.mp4');
    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(calls, isNot(contains('close')));
    await send(
      'SetAVTransportURI',
      '<CurrentURI>http://127.0.0.1/media.mp4</CurrentURI>',
    );
    await send('Play', '<Speed>1</Speed>');
    expect(playedUrls.last, 'http://127.0.0.1/media.mp4');

    // DASH Manifest 不交给 AVPlayer，回退窗口接收媒体和后续控制命令。
    final nativePlayCount = calls.where((call) => call == 'playUrl').length;
    await send(
      'SetAVTransportURI',
      '<CurrentURI>http://127.0.0.1/media.mpd</CurrentURI>',
    );
    await send('Play', '<Speed>1</Speed>');
    for (var i = 0; i < 20 && fallback.openedUrl == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(fallback.openedUrl, 'http://127.0.0.1/media.mpd');
    expect(
      (await send(
        'GetProtocolInfo',
        '',
        connection: true,
      )).contains('application/dash+xml'),
      isTrue,
    );
    expect(calls.where((call) => call == 'playUrl').length, nativePlayCount);
    await send('Pause', '');
    expect(fallback.commands, contains('dlnaPause'));
    await send('Seek', '<Unit>REL_TIME</Unit><Target>00:00:12</Target>');
    expect(fallback.commands, contains('dlnaSeek'));
    expect(
      (await send(
        'GetPositionInfo',
        '',
      )).contains('<RelTime>00:00:12</RelTime>'),
      isTrue,
    );
    await send(
      'SetAVTransportURI',
      '<CurrentURI>http://127.0.0.1/next-media.mpd</CurrentURI>',
    );
    await send('Play', '<Speed>1</Speed>');
    for (
      var i = 0;
      i < 20 && fallback.openedUrl != 'http://127.0.0.1/next-media.mpd';
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(fallback.openedUrl, 'http://127.0.0.1/next-media.mpd');
    expect(calls, isNot(contains('close')));
    await send('Stop', '');
    expect(fallback.isActive, isFalse);
    expect(calls, isNot(contains('close')));
    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(calls, contains('close'));
    expect(
      (await send('GetTransportInfo', '')).contains('NO_MEDIA_PRESENT'),
      isTrue,
    );
    await send(
      'SetAVTransportURI',
      '<CurrentURI>http://127.0.0.1/reconnected.mp4</CurrentURI>',
    );
    await send('Play', '<Speed>1</Speed>');
    expect(playedUrls.last, 'http://127.0.0.1/reconnected.mp4');

    // 鸿蒙版 B 站只设置 URI 并轮询状态；首次轮询应触发一次播放。
    await send(
      'SetAVTransportURI',
      '<CurrentURI>http://127.0.0.1/harmony-bili.mp4</CurrentURI>',
      userAgent: 'Linux/3.0.0 UPnP/1.0 Platinum/1.0.5.13',
    );
    final beforePoll = playedUrls.length;
    await send('GetPositionInfo', '');
    expect(playedUrls.length, beforePoll);
    expect(await send('GetTransportInfo', ''), contains('PLAYING'));
    expect(playedUrls.last, 'http://127.0.0.1/harmony-bili.mp4');
    await send('GetTransportInfo', '');
    expect(playedUrls.length, beforePoll + 1);

    // 控制端自己发送 Play 时，随后轮询不得重复打开窗口。
    await send(
      'SetAVTransportURI',
      '<CurrentURI>http://127.0.0.1/explicit-play.mp4</CurrentURI>',
      userAgent: 'Linux/3.0.0 UPnP/1.0 Platinum/1.0.5.13',
    );
    final beforeExplicitPlay = playedUrls.length;
    await send('Play', '<Speed>1</Speed>');
    await send('GetTransportInfo', '');
    expect(playedUrls.length, beforeExplicitPlay + 1);
  });
}

class _RecordingFallbackPlayer extends DlnaFallbackPlayer {
  _RecordingFallbackPlayer() : super(onStopped: () {}, onFailed: (_) {});

  String? openedUrl;
  final commands = <String>[];
  bool _active = false;
  Completer<void>? stopGate;
  Completer<void>? stopEntered;

  @override
  bool get isActive => _active;

  @override
  Future<bool> open(
    String url, {
    required String title,
    required String loadingText,
    required double volume,
    required bool muted,
  }) async {
    openedUrl = url;
    _active = true;
    return true;
  }

  @override
  Future<T?> invoke<T>(String method, [Object? arguments]) async {
    commands.add(method);
    if (method == 'dlnaPosition') return 12.0 as T;
    if (method == 'dlnaDuration') return 60.0 as T;
    return true as T;
  }

  @override
  Future<void> prepare() async {
    stopEntered?.complete();
    stopEntered = null;
    await stopGate?.future;
    stopGate = null;
    _active = false;
  }

  @override
  Future<void> stop() async {
    _active = false;
  }
}
