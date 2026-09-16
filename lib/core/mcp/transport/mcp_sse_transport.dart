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
    required Future<McpResponse?> Function(McpRequest request) onRequest,
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

        // 1. 健康检查端点 (/health)
        if (req.method == 'GET' && path == '/health') {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'status': 'ok',
            'server': 'anydeck',
            'clients': _activeSseClients.length,
          }));
          await req.response.close();
          return;
        }

        // 2. SSE 长连接端点 (GET 请求且为 text/event-stream 或特定路径)
        final acceptHeader = req.headers.value(HttpHeaders.acceptHeader) ?? '';
        final isSseGet = req.method == 'GET' &&
            (acceptHeader.contains('text/event-stream') ||
                path == '/sse' ||
                path == '/' ||
                path == '/mcp' ||
                path == '/events');

        if (isSseGet) {
          await _handleSseConnect(req);
          return;
        }

        // 3. 接收客户端请求端点 (支持 POST 到任意端点: /messages, /sse, /mcp, /rpc, / 等)
        if (req.method == 'POST') {
          await _handlePostMessage(req, onRequest);
          return;
        }

        // 4. 会话注销端点 (DELETE 请求)
        if (req.method == 'DELETE') {
          final sessionId = req.uri.queryParameters['sessionId'] ??
              req.uri.queryParameters['session_id'] ??
              req.headers.value('mcp-session-id') ??
              req.headers.value('x-session-id');
          if (sessionId != null) {
            final client = _activeSseClients.remove(sessionId);
            try {
              await client?.close();
            } catch (_) {}
          }
          req.response.statusCode = HttpStatus.ok;
          req.response.write(jsonEncode({'status': 'disconnected'}));
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
    final clientSessionId = req.headers.value('mcp-session-id') ??
        req.headers.value('x-session-id') ??
        req.uri.queryParameters['sessionId'] ??
        req.uri.queryParameters['session_id'] ??
        DateTime.now().millisecondsSinceEpoch.toString();

    final sessionId = clientSessionId;
    final res = req.response;

    res.headers.set('Content-Type', 'text/event-stream; charset=utf-8');
    res.headers.set('Cache-Control', 'no-cache, no-transform');
    res.headers.set('Connection', 'keep-alive');
    res.headers.set('Mcp-Session-Id', sessionId);
    res.headers.set('X-Session-Id', sessionId);

    _activeSseClients[sessionId] = res;

    // 向客户端发送 endpoint 初始化事件 (遵循 MCP SSE 规范标准格式)
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
    Future<McpResponse?> Function(McpRequest request) onRequest,
  ) async {
    final res = req.response;
    res.headers.contentType = ContentType.json;

    // 提取 Session ID，并在响应头中回写保持会话
    final sessionId = req.uri.queryParameters['sessionId'] ??
        req.uri.queryParameters['session_id'] ??
        req.headers.value('mcp-session-id') ??
        req.headers.value('x-session-id') ??
        (_activeSseClients.isNotEmpty ? _activeSseClients.keys.last : DateTime.now().millisecondsSinceEpoch.toString());

    res.headers.set('Mcp-Session-Id', sessionId);
    res.headers.set('X-Session-Id', sessionId);

    try {
      final body = await utf8.decoder.bind(req).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final mcpRequest = McpRequest.fromJson(json);

      final mcpResponse = await onRequest(mcpRequest);

      // 查找对应的 SSE 客户端
      HttpResponse? targetSseClient = _activeSseClients[sessionId];
      if (targetSseClient == null && _activeSseClients.isNotEmpty) {
        targetSseClient = _activeSseClients.values.last;
      }

      if (mcpResponse != null) {
        final responseBody = jsonEncode(mcpResponse.toJson());

        // 1. 如果有活跃的 SSE 连接，向 SSE 推送消息事件
        if (targetSseClient != null) {
          try {
            targetSseClient.write('event: message\ndata: $responseBody\n\n');
            await targetSseClient.flush();
          } catch (_) {}
        }

        // 2. HTTP POST 响应直接回写 JSON-RPC 结果 (完美适配 Streamable HTTP 与直连客户端)
        res.statusCode = HttpStatus.ok;
        res.write(responseBody);
      } else {
        // 通知类请求 (如 notifications/initialized)，规范规定无需返回数据
        res.statusCode = HttpStatus.accepted;
        res.write(jsonEncode({'status': 'accepted'}));
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
    res.headers.set('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
    res.headers.set(
      'Access-Control-Allow-Headers',
      'Origin, X-Requested-With, Content-Type, Accept, Authorization, Mcp-Session-Id, Mcp-Protocol-Version, X-Session-Id',
    );
    res.headers.set(
      'Access-Control-Expose-Headers',
      'Mcp-Session-Id, Mcp-Protocol-Version, X-Session-Id, Content-Type',
    );
  }

  @override
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;

    // 关闭连接会触发 done 回调修改 Map，先复制再遍历。
    final clients = _activeSseClients.values.toList();
    _activeSseClients.clear();
    for (final client in clients) {
      try {
        await client.close();
      } catch (_) {}
    }

    await _server?.close(force: true);
    _server = null;
  }
}
