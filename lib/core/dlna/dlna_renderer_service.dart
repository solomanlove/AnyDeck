import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'dlna_protocol.dart';
import 'dlna_discovery_address.dart';
import 'dlna_player_bridge.dart';
import 'dlna_fallback_player.dart';

part 'dlna_renderer_name.dart';
part 'dlna_renderer_control.dart';
part 'dlna_renderer_discovery.dart';

/// macOS DLNA MediaRenderer：SSDP 发现、UPnP 控制与原生播放器生命周期。
class DlnaRendererService extends ChangeNotifier {
  DlnaRendererService._({
    int httpPort = _defaultHttpPort,
    bool discovery = true,
    DlnaFallbackPlayer? fallback,
    Duration stopWindowDelay = const Duration(seconds: 5),
  }) : _configuredHttpPort = httpPort,
       _discoveryEnabled = discovery,
       _stopWindowDelay = stopWindowDelay {
    _fallback =
        fallback ??
        DlnaFallbackPlayer(
          onStopped: () {
            _endMediaSession();
          },
          onFailed: (detail) {
            _transportState = 'STOPPED';
            _error = detail;
            debugPrint('[DLNA] libmpv playback failed: $detail');
            notifyListeners();
            unawaited(_notifySubscribers());
          },
        );
    _player.setMethodCallHandler((call) async {
      if (call.method == 'playerStopped') {
        final arguments = call.arguments;
        if (arguments is Map && arguments['generation'] == _mediaGeneration) {
          _endMediaSession();
        }
      } else if (call.method == 'playerFailed') {
        final arguments = call.arguments;
        if (arguments is Map && arguments['generation'] == _mediaGeneration) {
          await _handleNativeFailure(
            '${arguments['detail']}',
            arguments['generation'] as int,
          );
        }
      }
    });
  }

  @visibleForTesting
  DlnaRendererService.forTest({
    DlnaFallbackPlayer? fallback,
    Duration stopWindowDelay = const Duration(seconds: 5),
  }) : this._(
         httpPort: 0,
         discovery: false,
         fallback: fallback,
         stopWindowDelay: stopWindowDelay,
       );

  static final instance = DlnaRendererService._();
  static const _player = DlnaPlayerBridge.channel;
  static final _multicast = InternetAddress('239.255.255.250');
  static const _defaultHttpPort = 18583;
  final int _configuredHttpPort;
  final bool _discoveryEnabled;
  final Duration _stopWindowDelay;

  late final DlnaFallbackPlayer _fallback;

  HttpServer? _http;
  RawDatagramSocket? _ssdp;
  StreamSubscription<RawSocketEvent>? _ssdpSubscription;
  Timer? _advertiseTimer;
  Timer? _stopWindowTimer;
  bool _starting = false;
  Future<void>? _fallbackOperation;
  Future<void>? _playerReset;
  bool _dashSource = false;
  int _mediaGeneration = 0;
  int? _pendingPlatinumPlayGeneration;
  String _serverName = DlnaProtocol.serverName;
  String _loadingText = '';
  String? _currentUrl;
  String _currentMetadata = '';
  String _transportState = 'NO_MEDIA_PRESENT';
  String? _error;
  final Map<String, _DlnaSubscription> _subscriptions = {};
  final Map<String, ({Future<InternetAddress?> address, DateTime expires})>
  _discoveryAddressCache = {};
  int _nextSubscription = 0;

  bool get isRunning => _http != null && (_ssdp != null || !_discoveryEnabled);
  int get httpPort => _http?.port ?? _configuredHttpPort;
  bool get isBusy => _starting;
  String? get error => _error;
  void _notifyNameChange() => notifyListeners();
  void _notifyControlChange() => notifyListeners();

  /// 用户关窗或 Stop 等待期结束后清除会话；下一次投屏需重新设置媒体地址。
  void _endMediaSession() {
    _stopWindowTimer?.cancel();
    _stopWindowTimer = null;
    _mediaGeneration++;
    _pendingPlatinumPlayGeneration = null;
    _currentUrl = null;
    _currentMetadata = '';
    _dashSource = false;
    _transportState = 'NO_MEDIA_PRESENT';
    notifyListeners();
    unawaited(_notifySubscribers());
  }

  /// 播放窗口的加载文案由主窗口当前语言提供。
  Future<void> setLoadingText(String value) async {
    if (_loadingText == value) return;
    _loadingText = value;
    await _player.invokeMethod<void>('setLoadingText', value);
    if (_fallback.hasWindow) {
      await _fallback.invoke<bool>('dlnaSetLoadingText', value);
    }
  }

  Future<void> start() async {
    if (isRunning || _starting) return;
    if (!Platform.isMacOS) {
      throw UnsupportedError('DLNA receiver supports macOS only');
    }
    _starting = true;
    _error = null;
    notifyListeners();
    try {
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        _configuredHttpPort,
      );
      _http = server;
      server.listen(_serve, onError: (Object error) => _error = '$error');
      if (!_discoveryEnabled) return;
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        1900,
        reuseAddress: true,
        reusePort: true,
      );
      _ssdp = socket;
      socket.broadcastEnabled = true;
      socket.multicastLoopback = false;
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      )) {
        try {
          socket.joinMulticast(_multicast, interface);
        } catch (error) {
          debugPrint('[DLNA] multicast on ${interface.name}: $error');
        }
      }
      _ssdpSubscription = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          Datagram? datagram;
          while ((datagram = socket.receive()) != null) {
            _handleSearch(datagram!);
          }
        }
      });
      await _advertise(alive: true);
      _advertiseTimer = Timer.periodic(
        const Duration(minutes: 4),
        (_) => unawaited(_advertise(alive: true)),
      );
    } catch (error) {
      _error = '$error';
      await stop();
      rethrow;
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _stopWindowTimer?.cancel();
    _stopWindowTimer = null;
    _advertiseTimer?.cancel();
    _advertiseTimer = null;
    if (_ssdp != null) await _advertise(alive: false);
    await _ssdpSubscription?.cancel();
    _ssdpSubscription = null;
    _ssdp?.close();
    _ssdp = null;
    await _http?.close(force: true);
    _http = null;
    _currentUrl = null;
    _currentMetadata = '';
    _mediaGeneration++;
    _dashSource = false;
    _transportState = 'NO_MEDIA_PRESENT';
    _subscriptions.clear();
    _discoveryAddressCache.clear();
    try {
      await _resetPlayers(keepWindow: false);
    } catch (error) {
      debugPrint('[DLNA] stop player failed: $error');
    }
    notifyListeners();
  }

  /// AVPlayer 报错后只对当前仍在播放的媒体执行一次 libmpv 回退。
  Future<void> _handleNativeFailure(String detail, int generation) async {
    debugPrint('[DLNA] AVPlayer failed: $detail');
    await _openFallback(detail, generation: generation, stopNative: true);
  }

  /// 切源只清空画面；真正结束投屏时才销毁窗口。
  Future<void> _resetPlayers({
    required bool keepWindow,
    int? expectedGeneration,
  }) async {
    final previous = _playerReset;
    final operation = () async {
      if (previous != null) await previous;
      if (expectedGeneration != null &&
          expectedGeneration != _mediaGeneration) {
        return;
      }
      if (keepWindow) {
        await _fallback.prepare();
        await _player.invokeMethod<void>('prepare', _loadingText);
      } else {
        await _fallback.stop();
        await _player.invokeMethod<void>('close');
      }
    }();
    _playerReset = operation;
    try {
      await operation;
    } finally {
      if (identical(_playerReset, operation)) _playerReset = null;
    }
  }

  Future<void> _openFallback(
    String detail, {
    required int generation,
    required bool stopNative,
  }) async {
    while (true) {
      final pending = _fallbackOperation;
      if (pending == null) break;
      await pending;
    }
    final url = _currentUrl;
    if (generation != _mediaGeneration ||
        url == null ||
        _transportState != 'PLAYING') {
      return;
    }
    if (_fallback.isActive) return;
    final operation = Completer<void>();
    _fallbackOperation = operation.future;
    try {
      final volume = await DlnaPlayerBridge.readNumber(
        'getVolume',
        fallback: 1,
      );
      final muted = await _player.invokeMethod<bool>('getMute') ?? false;
      if (stopNative) {
        await _player.invokeMethod<void>('prepare', _loadingText);
      }
      debugPrint('[DLNA] starting libmpv fallback');
      final opened = await _fallback.open(
        url,
        title: _serverName,
        loadingText: _loadingText,
        volume: volume,
        muted: muted,
      );
      if (_mediaGeneration != generation || _transportState != 'PLAYING') {
        await _fallback.stop();
        return;
      }
      if (!opened) {
        _transportState = 'STOPPED';
        _error = '$detail; libmpv could not render a video frame';
      } else {
        await _player.invokeMethod<void>('stop');
        _error = null;
        debugPrint('[DLNA] libmpv fallback playing');
      }
    } catch (error) {
      if (_mediaGeneration != generation) return;
      _error = detail;
      _transportState = 'STOPPED';
      debugPrint('[DLNA] libmpv fallback exception: $error');
    } finally {
      _fallbackOperation = null;
      operation.complete();
      notifyListeners();
      unawaited(_notifySubscribers());
    }
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Server', 'macOS/1.0 UPnP/1.0 AnyDeck/1.0');
    try {
      final path = request.uri.path;
      debugPrint(
        '[DLNA] HTTP ${request.method} $path from=${request.connectionInfo?.remoteAddress.address}',
      );
      if (request.method == 'GET' && path == '/device.xml') {
        response.headers.contentType = ContentType(
          'text',
          'xml',
          charset: 'utf-8',
        );
        final host =
            request.headers.value(HttpHeaders.hostHeader) ??
            '127.0.0.1:${_http!.port}';
        response.write(
          DlnaProtocol.deviceDescription('http://$host', name: _serverName),
        );
      } else if (request.method == 'GET' &&
          [
            '/avtransport.xml',
            '/rendering.xml',
            '/connection.xml',
          ].contains(path)) {
        response.headers.contentType = ContentType(
          'text',
          'xml',
          charset: 'utf-8',
        );
        response.write(
          DlnaProtocol.serviceDescription(path.substring(1, path.length - 4)),
        );
      } else if (request.method == 'POST' && path.endsWith('/control')) {
        await _control(request);
      } else if (request.method == 'SUBSCRIBE' && path.endsWith('/event')) {
        final previousSid = request.headers.value('SID');
        if (previousSid != null && _subscriptions.containsKey(previousSid)) {
          _subscriptions[previousSid]!.expires = DateTime.now().add(
            const Duration(minutes: 5),
          );
          response.headers.set('SID', previousSid);
          response.headers.set('TIMEOUT', 'Second-300');
        } else {
          final rawCallback = request.headers.value('CALLBACK');
          final callback = rawCallback == null
              ? null
              : Uri.tryParse(rawCallback.replaceAll(RegExp(r'[<>]'), ''));
          final remote = request.connectionInfo?.remoteAddress.address;
          if (callback == null ||
              callback.scheme != 'http' ||
              callback.host != remote) {
            response.statusCode = HttpStatus.preconditionFailed;
          } else {
            final sid = 'uuid:${DlnaProtocol.uuid}-${++_nextSubscription}';
            _subscriptions[sid] = _DlnaSubscription(callback, path);
            response.headers.set('SID', sid);
            response.headers.set('TIMEOUT', 'Second-300');
            unawaited(
              Future<void>.delayed(
                const Duration(milliseconds: 100),
                () => _notifySubscribers(),
              ),
            );
          }
        }
      } else if (request.method == 'UNSUBSCRIBE' && path.endsWith('/event')) {
        _subscriptions.remove(request.headers.value('SID'));
        response.statusCode = HttpStatus.ok;
      } else {
        response.statusCode = HttpStatus.notFound;
      }
    } catch (error) {
      debugPrint('[DLNA] request failed: $error');
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      await response.close();
    }
  }

  Future<void> _control(HttpRequest request) async {
    final response = request.response;
    final body = await utf8.decoder.bind(request).join();
    if (body.length > 1024 * 1024 ||
        body.contains('<!DOCTYPE') ||
        body.contains('<!ENTITY')) {
      response.statusCode = HttpStatus.badRequest;
      return;
    }
    final service = request.uri.path.split('/')[1];
    final type = switch (service) {
      'avtransport' => DlnaProtocol.transportType,
      'rendering' => DlnaProtocol.renderingType,
      'connection' => DlnaProtocol.connectionType,
      _ => '',
    };
    final soapAction =
        request.headers.value('SOAPACTION')?.replaceAll('"', '').trim() ?? '';
    final action = soapAction.split('#').last;
    if ([
      'SetAVTransportURI',
      'Play',
      'Pause',
      'Stop',
      'Seek',
    ].contains(action)) {
      debugPrint('[DLNA] SOAP $service/$action');
    }
    if (type.isEmpty || !soapAction.startsWith(type) || action.isEmpty) {
      response.statusCode = HttpStatus.badRequest;
      return;
    }
    final values = await _dispatch(
      action,
      body,
      userAgent: request.headers.value(HttpHeaders.userAgentHeader),
    );
    response.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
    final payload = values == null
        ? DlnaProtocol.soapFault
        : DlnaProtocol.soapResponse(type, action, values);
    if (values == null) {
      response.statusCode = HttpStatus.internalServerError;
    }
    // SOAP 响应写入明确长度，兼容不解析 chunked 响应的 DLNA 控制端。
    final bytes = utf8.encode(payload);
    response.contentLength = bytes.length;
    response.add(bytes);
  }

  Future<void> _notifySubscribers() async {
    final now = DateTime.now();
    _subscriptions.removeWhere(
      (_, subscription) => subscription.expires.isBefore(now),
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      for (final entry in _subscriptions.entries.toList()) {
        try {
          final state = entry.value;
          final volume = state.path.startsWith('/rendering/')
              ? await DlnaPlayerBridge.readNumber('getVolume', fallback: 1)
              : 1.0;
          final lastChange = state.path.startsWith('/rendering/')
              ? '<Event xmlns="urn:schemas-upnp-org:metadata-1-0/RCS/"><InstanceID val="0"><Volume channel="Master" val="${(volume * 100).round()}"/></InstanceID></Event>'
              : '<Event xmlns="urn:schemas-upnp-org:metadata-1-0/AVT/"><InstanceID val="0"><TransportState val="$_transportState"/></InstanceID></Event>';
          final property = state.path.startsWith('/connection/')
              ? '<SinkProtocolInfo>${DlnaProtocol.sinkProtocolInfo}</SinkProtocolInfo>'
              : '<LastChange>${DlnaProtocol.escape(lastChange)}</LastChange>';
          final body =
              '<?xml version="1.0"?><e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0"><e:property>$property</e:property></e:propertyset>';
          final request = await client
              .openUrl('NOTIFY', state.callback)
              .timeout(const Duration(seconds: 3));
          request.headers.set('NT', 'upnp:event');
          request.headers.set('NTS', 'upnp:propchange');
          request.headers.set('SID', entry.key);
          request.headers.set('SEQ', '${state.sequence++}');
          request.headers.contentType = ContentType(
            'text',
            'xml',
            charset: 'utf-8',
          );
          request.write(body);
          await request.close().timeout(const Duration(seconds: 3));
        } catch (error) {
          debugPrint('[DLNA] event delivery failed: $error');
        }
      }
    } finally {
      client.close(force: true);
    }
  }
}
