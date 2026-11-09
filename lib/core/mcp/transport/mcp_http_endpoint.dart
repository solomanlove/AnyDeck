import 'dart:convert';
import 'dart:io';
import '../models/mcp_request.dart';
import '../models/mcp_response.dart';
import '../models/mcp_server_config.dart';

/// 平台 Streamable HTTP 端点；逐请求处理，不借用旧 SSE 客户端会话。
class McpHttpEndpoint {
  McpHttpEndpoint({required this.config, required this.onRequest});
  final McpServerConfig Function() config;
  final Future<McpResponse?> Function(
    McpRequest request,
    String platform,
    String version,
  )
  onRequest;
  int _active = 0;
  static const versions = ['2026-07-28', '2025-11-25'];

  Future<void> handle(HttpRequest req, String platform) async {
    final res = req.response;
    if (config().disabledPlatforms.contains(platform)) {
      res.statusCode = 503;
      await res.close();
      return;
    }
    final token = config().platformTokens[platform];
    if (token == null ||
        token.isEmpty ||
        req.headers.value('authorization') != 'Bearer $token') {
      res.statusCode = 401;
      await res.close();
      return;
    }
    if (req.method != 'POST') {
      res.statusCode = 405;
      res.headers.set('Allow', 'POST');
      await res.close();
      return;
    }
    if (_active >= 4) {
      res.statusCode = 429;
      await res.close();
      return;
    }
    _active++;
    dynamic id;
    try {
      final body = <int>[];
      await for (final chunk in req.timeout(const Duration(seconds: 10))) {
        body.addAll(chunk);
        if (body.length > 1024 * 1024) {
          res.statusCode = 413;
          await res.close();
          return;
        }
      }
      final json = jsonDecode(utf8.decode(body));
      if (json is! Map<String, dynamic>) {
        throw const FormatException('请求必须是 JSON object');
      }
      final request = McpRequest.fromJson(json);
      id = request.id;
      final accept = req.headers.value('accept') ?? '';
      if (!accept.contains('application/json') ||
          !accept.contains('text/event-stream')) {
        res.statusCode = 406;
        await res.close();
        return;
      }
      if (req.headers.contentType?.mimeType != 'application/json') {
        res.statusCode = 415;
        await res.close();
        return;
      }
      final version =
          req.headers.value('mcp-protocol-version') ??
          (request.method == 'initialize'
              ? (request.params?['protocolVersion'] as String?)
              : null);
      if (!versions.contains(version)) {
        await _reply(
          res,
          McpResponse.error(
            id: id,
            code: -32022,
            message: 'Unsupported protocol version',
            data: {'supported': versions, 'requested': version},
          ),
          400,
        );
        return;
      }
      if (version == '2026-07-28') {
        final meta = request.params?['_meta'];
        final expectedName = request.params?['name'] ?? request.params?['uri'];
        if (meta is! Map ||
            meta['io.modelcontextprotocol/protocolVersion'] != version ||
            meta['io.modelcontextprotocol/clientCapabilities'] is! Map ||
            req.headers.value('mcp-method') != request.method ||
            (const {
                  'tools/call',
                  'resources/read',
                  'prompts/get',
                }.contains(request.method) &&
                _decodeHeader(req.headers.value('mcp-name')) != expectedName)) {
          await _reply(
            res,
            McpResponse.error(
              id: id,
              code: -32020,
              message: 'Header mismatch or missing request metadata',
            ),
            400,
          );
          return;
        }
      }
      final response = await onRequest(request, platform, version!);
      if (response == null) {
        res.statusCode = 202;
        await res.close();
      } else {
        await _reply(res, response, response.error?.code == -32601 ? 404 : 200);
      }
    } on FormatException catch (e) {
      await _reply(
        res,
        McpResponse.error(id: id, code: -32700, message: e.message),
        400,
      );
    } catch (_) {
      await _reply(
        res,
        McpResponse.error(id: id, code: -32600, message: 'Invalid MCP request'),
        400,
      );
    } finally {
      _active--;
    }
  }

  String? _decodeHeader(String? value) {
    if (value != null &&
        value.startsWith('=?base64?') &&
        value.endsWith('?=')) {
      return utf8.decode(base64Decode(value.substring(9, value.length - 2)));
    }
    return value;
  }

  Future<void> _reply(
    HttpResponse res,
    McpResponse response,
    int status,
  ) async {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(response.toJson()));
    await res.close();
  }
}
