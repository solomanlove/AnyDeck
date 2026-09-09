import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/mcp_request.dart';
import '../models/mcp_response.dart';
import 'mcp_transport_interface.dart';

/// 基于 HTTP + Server-Sent Events (SSE) 的 MCP 传输适配器
class McpSseTransport implements McpTransportInterface {
  final String host;
  final int port;
  final bool enableAuth;
  final String authToken;

  HttpServer? _server;
  bool _isRunning = false;

  /// 保存活动的 SSE 客户端连接 (sessionId -> HttpResponse)
  final Map<String, HttpResponse> _activeSseClients = {};

  McpSseTransport({
    this.host = '127.0.0.1',
    this.port = 8765,
    this.enableAuth = false,
    this.authToken = '',
  });

  @override
  String get name => 'SSE (HTTP $host:$port)';

  @override
  bool get isRunning => _isRunning;

  /// 活动连接客户端数量
  int get clientCount => _activeSseClients.length;

  @override
  Future<void> start({
    required Future<McpResponse> Function(McpRequest request) onRequest,
  }) async {
    if (_isRunning) return;

    try {
      _server = await HttpServer.bind(host, port, shared: true);
      _isRunning = true;

      _server!.listen((HttpRequest req) async {
        _setCorsHeaders(req.response);

        // 处理 OPTIONS 预检请求
        if (req.method == 'OPTIONS') {
          req.response.statusCode = HttpStatus.noContent;
          await req.response.close();
          return;
        }

        // 鉴权校验
        if (enableAuth && authToken.isNotEmpty) {
          final authHeader = req.headers.value(HttpHeaders.authorizationHeader);
          final queryToken = req.uri.queryParameters['token'];
          final isAuthorized = authHeader == 'Bearer $authToken' || queryToken == authToken;

          if (!isAuthorized) {
            req.response.statusCode = HttpStatus.unauthorized;
            req.response.write(jsonEncode({'error': 'Unauthorized: Invalid token'}));
            await req.response.close();
            return;
          }
        }

        final path = req.uri.path;

        // 1. SSE 长连接端点 (/sse)
        if (req.method == 'GET' && (path == '/sse' || path == '/')) {
          await _handleSseConnect(req);
          return;
        }

        // 2. 接收客户端请求端点 (/messages 或 POST /)
        if (req.method == 'POST' && (path == '/messages' || path == '/rpc' || path == '/')) {
          await _handlePostMessage(req, onRequest);
          return;
        }

        // 3. 健康检查端点 (/health)
        if (req.method == 'GET' && path == '/health') {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'status': 'ok',
            'server': 'AnyDeck MCP Server',
            'clients': _activeSseClients.length,
          }));
          await req.response.close();
          return;
        }

        // 404 默认
        req.response.statusCode = HttpStatus.notFound;
        req.response.write('Not Found');
        await req.response.close();
      });
    } catch (e) {
      _isRunning = false;
      rethrow;
    }
  }

  /// 处理 SSE 客户端接入
  Future<void> _handleSseConnect(HttpRequest req) async {
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final res = req.response;

    res.headers.set('Content-Type', 'text/event-stream; charset=utf-8');
    res.headers.set('Cache-Control', 'no-cache, no-transform');
    res.headers.set('Connection', 'keep-alive');

    _activeSseClients[sessionId] = res;

    // 向客户端发送 endpoint 初始化事件
    final endpointUri = '/messages?sessionId=$sessionId';
    res.write('event: endpoint\ndata: $endpointUri\n\n');
    await res.flush();

    req.response.done.then((_) {
      _activeSseClients.remove(sessionId);
    }).catchError((_) {
      _activeSseClients.remove(sessionId);
    });
  }

  /// 处理客户端发来的 POST 请求
  Future<void> _handlePostMessage(
    HttpRequest req,
    Future<McpResponse> Function(McpRequest request) onRequest,
  ) async {
    final res = req.response;
    res.headers.contentType = ContentType.json;

    try {
      final body = await utf8.decoder.bind(req).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final mcpRequest = McpRequest.fromJson(json);

      final mcpResponse = await onRequest(mcpRequest);
      final responseBody = jsonEncode(mcpResponse.toJson());

      // 检查是否有对应的 SSE 客户端会话
      final sessionId = req.uri.queryParameters['sessionId'];
      if (sessionId != null && _activeSseClients.containsKey(sessionId)) {
        final sseRes = _activeSseClients[sessionId]!;
        sseRes.write('event: message\ndata: $responseBody\n\n');
        await sseRes.flush();

        res.statusCode = HttpStatus.accepted;
        res.write(jsonEncode({'status': 'sent_to_sse'}));
      } else {
        // 直接作为 HTTP 响应返回
        res.statusCode = HttpStatus.ok;
        res.write(responseBody);
      }
    } catch (e) {
      res.statusCode = HttpStatus.badRequest;
      res.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': McpError.invalidRequest, 'message': '请求处理失败: $e'},
      }));
    } finally {
      await res.close();
    }
  }

  /// 设置 CORS 跨域响应头
  void _setCorsHeaders(HttpResponse res) {
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.headers.set(
      'Access-Control-Allow-Headers',
      'Origin, X-Requested-With, Content-Type, Accept, Authorization',
    );
  }

  @override
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;

    for (final client in _activeSseClients.values) {
      try {
        await client.close();
      } catch (_) {}
    }
    _activeSseClients.clear();

    await _server?.close(force: true);
    _server = null;
  }
}
