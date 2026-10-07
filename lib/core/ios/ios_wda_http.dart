import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 真正的异步 WDA HTTP 客户端；HTTP/W3C 错误均抛出，不把收到响应当作成功。
class IosWdaHttp {
  IosWdaHttp(this.port, {this.timeout = const Duration(seconds: 8)});
  final int port;
  final Duration timeout;
  final HttpClient _http = HttpClient();
  String? sessionId;

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    HttpClientRequest? active;
    var cancelled = false;
    try {
      return await (() async {
        final request = await _http.openUrl(
          method,
          Uri.http('127.0.0.1:$port', path),
        );
        active = request;
        if (cancelled) {
          request.abort();
          throw TimeoutException('WDA request cancelled');
        }
        request.headers.contentType = ContentType.json;
        // WDA 的 HTTP 服务不接受 chunked 请求；长度必须按 UTF-8 字节计算。
        final payload = body == null
            ? const <int>[]
            : utf8.encode(jsonEncode(body));
        request.contentLength = payload.length;
        if (payload.isNotEmpty) request.add(payload);
        final response = await request.close();
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 8 * 1024 * 1024) {
            throw const FormatException('WDA response exceeds 8 MiB');
          }
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Invalid WDA response');
        }
        final value = decoded['value'];
        if (response.statusCode < 200 ||
            response.statusCode >= 300 ||
            (value is Map && value['error'] != null) ||
            (decoded['status'] is num && decoded['status'] != 0)) {
          throw StateError(
            'WDA HTTP ${response.statusCode}: ${value is Map ? value['message'] ?? value : value}',
          );
        }
        return decoded;
      })().timeout(timeout);
    } catch (_) {
      cancelled = true;
      active?.abort();
      rethrow;
    }
  }

  Future<void> createSession() async {
    final response = await request(
      '/session',
      method: 'POST',
      body: {
        'capabilities': {
          'alwaysMatch': {'shouldUseCompactResponses': true},
        },
      },
    );
    final value = response['value'];
    sessionId =
        (response['sessionId'] ?? (value is Map ? value['sessionId'] : null))
            as String?;
    if (sessionId == null || sessionId!.isEmpty) {
      throw StateError('WDA did not return a session');
    }
  }

  String path(String suffix) {
    if (sessionId == null) throw StateError('iosWdaUnavailable');
    return '/session/$sessionId$suffix';
  }

  Future<Map<String, dynamic>> geometry() async {
    final size = (await request(path('/window/size')))['value'];
    final orientation = (await request(path('/orientation')))['value'];
    if (size is! Map ||
        size['width'] is! num ||
        size['height'] is! num ||
        (size['width'] as num) <= 0 ||
        (size['height'] as num) <= 0) {
      throw StateError('Invalid WDA window size');
    }
    return {
      'width': size['width'],
      'height': size['height'],
      'orientation': orientation,
    };
  }

  /// 坐标单位为 iOS point；W3C action 在一次请求内表达完整手势。
  Future<void> gesture(
    double x,
    double y, {
    double? toX,
    double? toY,
    int durationMs = 400,
  }) async {
    if (![x, y, toX ?? x, toY ?? y].every((n) => n.isFinite && n >= 0)) {
      throw ArgumentError('Invalid touch coordinates');
    }
    await request(
      path('/actions'),
      method: 'POST',
      body: {
        'actions': [
          {
            'type': 'pointer',
            'id': 'anydeck-finger',
            'parameters': {'pointerType': 'touch'},
            'actions': [
              {
                'type': 'pointerMove',
                'duration': 0,
                'x': x.round(),
                'y': y.round(),
                'origin': 'viewport',
              },
              {'type': 'pointerDown', 'button': 0},
              {'type': 'pause', 'duration': toX == null ? 60 : 80},
              if (toX != null && toY != null)
                {
                  'type': 'pointerMove',
                  'duration': durationMs.clamp(100, 2000),
                  'x': toX.round(),
                  'y': toY.round(),
                  'origin': 'viewport',
                },
              {'type': 'pointerUp', 'button': 0},
            ],
          },
        ],
      },
    );
  }

  void close() => _http.close(force: true);
}
