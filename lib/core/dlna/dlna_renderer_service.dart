import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dlna_protocol.dart';

/// macOS DLNA MediaRenderer：SSDP 发现、UPnP 控制与原生播放器生命周期。
class DlnaRendererService extends ChangeNotifier {
  DlnaRendererService._() {
    _player.setMethodCallHandler((call) async {
      if (call.method == 'playerStopped') {
        _transportState = 'STOPPED';
        notifyListeners();
        unawaited(_notifySubscribers());
      }
    });
  }

  static final instance = DlnaRendererService._();
  static const _player = MethodChannel('any_deck/dlna_player');
  static final _multicast = InternetAddress('239.255.255.250');

  HttpServer? _http;
  RawDatagramSocket? _ssdp;
  StreamSubscription<RawSocketEvent>? _ssdpSubscription;
  Timer? _advertiseTimer;
  bool _starting = false;
  String? _currentUrl;
  String _transportState = 'NO_MEDIA_PRESENT';
  String? _error;
  final Map<String, _DlnaSubscription> _subscriptions = {};
  int _nextSubscription = 0;

  bool get isRunning => _http != null && _ssdp != null;
  bool get isBusy => _starting;
  String? get error => _error;

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
        0,
        shared: true,
      );
      _http = server;
      server.listen(_serve, onError: (Object error) => _error = '$error');
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
    _transportState = 'NO_MEDIA_PRESENT';
    _subscriptions.clear();
    try {
      await _player.invokeMethod<void>('stop');
    } catch (_) {}
    notifyListeners();
  }

  Future<List<InternetAddress>> _addresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return interfaces
        .expand((interface) => interface.addresses)
        .where((address) => !address.isLoopback && !address.isLinkLocal)
        .toList();
  }

  void _handleSearch(Datagram packet) {
    final text = ascii.decode(packet.data, allowInvalid: true);
    if (!text.toUpperCase().startsWith('M-SEARCH * HTTP/1.1')) return;
    final st = RegExp(
      r'^ST:\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(text)?.group(1)?.trim();
    if (st == null ||
        !['ssdp:all', ...DlnaProtocol.searchTargets].contains(st)) {
      return;
    }
    unawaited(_replySearch(packet.address, packet.port, st));
  }

  Future<void> _replySearch(
    InternetAddress destination,
    int port,
    String st,
  ) async {
    final socket = _ssdp;
    final server = _http;
    if (socket == null || server == null) return;
    for (final address in await _addresses()) {
      for (final target
          in st == 'ssdp:all' ? DlnaProtocol.searchTargets : [st]) {
        final usn = target.startsWith('uuid:')
            ? target
            : 'uuid:${DlnaProtocol.uuid}::$target';
        final message =
            'HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=300\r\nEXT:\r\nLOCATION: http://${address.address}:${server.port}/device.xml\r\nSERVER: macOS/1.0 UPnP/1.0 AdbManage/1.0\r\nST: $target\r\nUSN: $usn\r\n\r\n';
        socket.send(ascii.encode(message), destination, port);
      }
    }
  }

  Future<void> _advertise({required bool alive}) async {
    final socket = _ssdp;
    final server = _http;
    if (socket == null || server == null) return;
    for (final address in await _addresses()) {
      for (final target in DlnaProtocol.searchTargets) {
        final usn = target.startsWith('uuid:')
            ? target
            : 'uuid:${DlnaProtocol.uuid}::$target';
        final message =
            'NOTIFY * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nCACHE-CONTROL: max-age=300\r\nLOCATION: http://${address.address}:${server.port}/device.xml\r\nNT: $target\r\nNTS: ssdp:${alive ? 'alive' : 'byebye'}\r\nSERVER: macOS/1.0 UPnP/1.0 AdbManage/1.0\r\nUSN: $usn\r\n\r\n';
        socket.send(ascii.encode(message), _multicast, 1900);
      }
    }
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Server', 'macOS/1.0 UPnP/1.0 AdbManage/1.0');
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/device.xml') {
        response.headers.contentType = ContentType(
          'text',
          'xml',
          charset: 'utf-8',
        );
        final host =
            request.headers.value(HttpHeaders.hostHeader) ??
            '127.0.0.1:${_http!.port}';
        response.write(DlnaProtocol.deviceDescription('http://$host'));
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
    if (type.isEmpty || !soapAction.startsWith(type) || action.isEmpty) {
      response.statusCode = HttpStatus.badRequest;
      return;
    }
    final values = await _dispatch(action, body);
    response.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
    if (values == null) {
      response.statusCode = HttpStatus.internalServerError;
      response.write(DlnaProtocol.soapFault);
    } else {
      response.write(DlnaProtocol.soapResponse(type, action, values));
    }
  }

  Future<Map<String, String>?> _dispatch(String action, String body) async {
    switch (action) {
      case 'SetAVTransportURI':
        final raw = DlnaProtocol.element(body, 'CurrentURI')?.trim();
        final uri = raw == null ? null : Uri.tryParse(raw);
        if (uri == null ||
            !['http', 'https'].contains(uri.scheme) ||
            uri.host.isEmpty) {
          return null;
        }
        if (_transportState == 'PLAYING' ||
            _transportState == 'PAUSED_PLAYBACK') {
          await _player.invokeMethod<void>('stop');
        }
        _currentUrl = raw;
        _transportState = 'STOPPED';
        notifyListeners();
        unawaited(_notifySubscribers());
        return {};
      case 'Play':
        if (_currentUrl == null) return null;
        if (_transportState == 'PAUSED_PLAYBACK') {
          await _player.invokeMethod<void>('play');
        } else {
          await _player.invokeMethod<void>('playUrl', _currentUrl);
        }
        _transportState = 'PLAYING';
        notifyListeners();
        unawaited(_notifySubscribers());
        return {};
      case 'Pause':
        await _player.invokeMethod<void>('pause');
        _transportState = 'PAUSED_PLAYBACK';
        notifyListeners();
        unawaited(_notifySubscribers());
        return {};
      case 'Stop':
        await _player.invokeMethod<void>('stop');
        _transportState = 'STOPPED';
        notifyListeners();
        unawaited(_notifySubscribers());
        return {};
      case 'Seek':
        final target = DlnaProtocol.element(body, 'Target');
        final seconds = target == null ? null : DlnaProtocol.parseTime(target);
        if (seconds == null) return null;
        await _player.invokeMethod<void>('seek', seconds);
        return {};
      case 'GetTransportInfo':
        return {
          'CurrentTransportState': _transportState,
          'CurrentTransportStatus': 'OK',
          'CurrentSpeed': '1',
        };
      case 'GetPositionInfo':
        final seconds = await _player.invokeMethod<double>('position') ?? 0;
        final duration = await _player.invokeMethod<double>('duration') ?? 0;
        return {
          'Track': _currentUrl == null ? '0' : '1',
          'TrackDuration': DlnaProtocol.formatTime(duration),
          'TrackMetaData': '',
          'TrackURI': _currentUrl ?? '',
          'RelTime': DlnaProtocol.formatTime(seconds),
          'AbsTime': DlnaProtocol.formatTime(seconds),
          'RelCount': '0',
          'AbsCount': '0',
        };
      case 'GetMediaInfo':
        return {
          'NrTracks': _currentUrl == null ? '0' : '1',
          'MediaDuration': DlnaProtocol.formatTime(
            await _player.invokeMethod<double>('duration') ?? 0,
          ),
          'CurrentURI': _currentUrl ?? '',
          'CurrentURIMetaData': '',
          'NextURI': '',
          'NextURIMetaData': '',
          'PlayMedium': 'NETWORK',
          'RecordMedium': 'NOT_IMPLEMENTED',
          'WriteStatus': 'NOT_IMPLEMENTED',
        };
      case 'GetDeviceCapabilities':
        return {
          'PlayMedia': 'NETWORK',
          'RecMedia': 'NOT_IMPLEMENTED',
          'RecQualityModes': 'NOT_IMPLEMENTED',
        };
      case 'GetTransportSettings':
        return {'PlayMode': 'NORMAL', 'RecQualityMode': 'NOT_IMPLEMENTED'};
      case 'GetProtocolInfo':
        return {
          'Source': '',
          'Sink':
              'http-get:*:video/mp4:*,http-get:*:application/vnd.apple.mpegurl:*',
        };
      case 'GetCurrentConnectionIDs':
        return {'ConnectionIDs': '0'};
      case 'GetCurrentConnectionInfo':
        return {
          'RcsID': '0',
          'AVTransportID': '0',
          'ProtocolInfo': 'http-get:*:video/mp4:*',
          'PeerConnectionManager': '',
          'PeerConnectionID': '-1',
          'Direction': 'Input',
          'Status': 'OK',
        };
      case 'SetVolume':
        final volume = int.tryParse(
          DlnaProtocol.element(body, 'DesiredVolume') ?? '',
        );
        if (volume == null) return null;
        await _player.invokeMethod<void>(
          'setVolume',
          volume.clamp(0, 100) / 100,
        );
        return {};
      case 'GetVolume':
        final volume = await _player.invokeMethod<double>('getVolume') ?? 1;
        return {'CurrentVolume': '${(volume * 100).round()}'};
      case 'SetMute':
        await _player.invokeMethod<void>(
          'setVolume',
          DlnaProtocol.element(body, 'DesiredMute') == '1' ? 0.0 : 1.0,
        );
        return {};
      case 'GetMute':
        final volume = await _player.invokeMethod<double>('getVolume') ?? 1;
        return {'CurrentMute': volume == 0 ? '1' : '0'};
      default:
        return null;
    }
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
              ? await _player.invokeMethod<double>('getVolume') ?? 1
              : 1.0;
          final lastChange = state.path.startsWith('/rendering/')
              ? '<Event xmlns="urn:schemas-upnp-org:metadata-1-0/RCS/"><InstanceID val="0"><Volume channel="Master" val="${(volume * 100).round()}"/></InstanceID></Event>'
              : '<Event xmlns="urn:schemas-upnp-org:metadata-1-0/AVT/"><InstanceID val="0"><TransportState val="$_transportState"/></InstanceID></Event>';
          final property = state.path.startsWith('/connection/')
              ? '<SinkProtocolInfo>http-get:*:video/mp4:*,http-get:*:application/vnd.apple.mpegurl:*</SinkProtocolInfo>'
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

class _DlnaSubscription {
  _DlnaSubscription(this.callback, this.path);

  final Uri callback;
  final String path;
  DateTime expires = DateTime.now().add(const Duration(minutes: 5));
  int sequence = 0;
}
