import 'dart:convert';
import 'dart:async';
import 'package:any_deck/core/mcp/models/mcp_response.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/mcp/mcp_server.dart';
import 'package:any_deck/core/mcp/models/mcp_server_config.dart';
import 'package:any_deck/core/mcp/models/mcp_tool_definition.dart';
import 'package:any_deck/core/mcp/registry/mcp_tool_registry.dart';

/// 用真实 HTTP socket 验证多客户端隔离，设备处理器为无副作用模拟。
void main() {
  late McpServer server;
  late HttpClient client;
  late int port;
  var calls = 0;
  setUp(() async {
    calls = 0;
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = socket.port;
    await socket.close();
    final registry = McpToolRegistry()
      ..resolvePlatform = (id) async =>
          const {'a': 'android', 'h': 'harmony', 'i': 'ios'}[id];
    for (final platform in ['android', 'harmony', 'ios']) {
      registry.register(
        McpToolDefinition(
          name: '${platform}_probe',
          category: 'device',
          platforms: {platform},
          readOnly: true,
          description: '平台模拟读取',
          inputSchema: const {
            'type': 'object',
            'required': ['deviceId'],
            'properties': {
              'deviceId': {'type': 'string'},
            },
          },
          handler: (args) async {
            calls++;
            return {'deviceId': args['deviceId'], 'platform': platform};
          },
        ),
      );
    }
    registry.register(
      McpToolDefinition(
        name: 'dangerous',
        isDangerous: true,
        description: '危险模拟',
        inputSchema: const {'type': 'object'},
        handler: (_) async {
          calls++;
          return {};
        },
      ),
    );
    server = McpServer(
      registry: registry,
      config: McpServerConfig(
        port: port,
        platformTokens: const {
          'android': 'a-token',
          'harmony': 'h-token',
          'ios': 'i-token',
        },
      ),
    );
    await server.startSse();
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  Future<(int, Map<String, dynamic>)> call(
    String platform,
    String method, {
    Map<String, dynamic> params = const {},
    String? token,
    String? origin,
    bool mismatch = false,
    bool modern = true,
  }) async {
    final req = await client.postUrl(
      Uri.parse('http://127.0.0.1:$port/mcp/$platform'),
    );
    req.headers.contentType = ContentType.json;
    req.headers.set('accept', 'application/json, text/event-stream');
    req.headers.set(
      'authorization',
      'Bearer ${token ?? '${platform[0]}-token'}',
    );
    req.headers.set(
      'mcp-protocol-version',
      modern ? '2026-07-28' : '2025-11-25',
    );
    req.headers.set('mcp-method', mismatch ? 'ping' : method);
    if (params['name'] != null) req.headers.set('mcp-name', params['name']);
    if (origin != null) req.headers.set('origin', origin);
    req.write(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 'same-id',
        'method': method,
        'params': {
          ...params,
          if (modern)
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': {},
            },
        },
      }),
    );
    final res = await req.close();
    final body = await utf8.decoder.bind(res).join();
    return (
      res.statusCode,
      body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>,
    );
  }

  test('三个并发客户端仅获得本平台工具，同一个 request id 不串线', () async {
    final responses = await Future.wait(
      ['android', 'harmony', 'ios'].map((p) => call(p, 'tools/list')),
    );
    for (var n = 0; n < responses.length; n++) {
      final p = ['android', 'harmony', 'ios'][n];
      expect(responses[n].$1, 200);
      final result = responses[n].$2['result'];
      expect(result['resultType'], 'complete');
      final names = (result['tools'] as List).map((t) => t['name']).toList();
      expect(names, contains('${p}_probe'));
      expect(
        names.where((name) => name.toString().endsWith('_probe')).length,
        1,
      );
    }
  });
  test('跨入口工具、跨平台设备和未知设备在 handler 前被拒绝', () async {
    for (final args in [
      {
        'name': 'ios_probe',
        'arguments': {'deviceId': 'i'},
      },
      {
        'name': 'android_probe',
        'arguments': {'deviceId': 'i'},
      },
      {
        'name': 'android_probe',
        'arguments': {'deviceId': 'unknown'},
      },
      {
        'name': 'android_probe',
        'arguments': {'deviceId': 3},
      },
    ]) {
      final r = await call('android', 'tools/call', params: args);
      expect(r.$2['result']['isError'], true);
    }
    expect(calls, 0);
  });
  test('同平台调用成功，高危调用真正被阻止', () async {
    final r = await call(
      'harmony',
      'tools/call',
      params: {
        'name': 'harmony_probe',
        'arguments': {'deviceId': 'h'},
      },
    );
    expect(r.$2['result']['structuredContent']['platform'], 'harmony');
    expect(calls, 1);
    final blocked = await call(
      'android',
      'tools/call',
      params: {'name': 'dangerous'},
    );
    expect(blocked.$2['result']['isError'], true);
    expect(calls, 1);
  });
  test('凭据不能跨平台使用，Origin 和 Header 必须匹配', () async {
    expect((await call('ios', 'tools/list', token: 'a-token')).$1, 401);
    expect(
      (await call('ios', 'tools/list', origin: 'https://evil.example')).$1,
      403,
    );
    final r = await call('ios', 'tools/list', mismatch: true);
    expect(r.$1, 400);
    expect(r.$2['error']['code'], -32020);
  });
  test('支持现代 discovery 和旧客户端 initialize；关闭入口及时生效', () async {
    final modern = await call('ios', 'server/discover');
    expect(modern.$2['result']['supportedVersions'], contains('2026-07-28'));
    final legacy = await call(
      'ios',
      'initialize',
      modern: false,
      params: {
        'protocolVersion': '2025-11-25',
        'capabilities': {},
        'clientInfo': {'name': 'test', 'version': '1'},
      },
    );
    expect(legacy.$2['result']['serverInfo']['name'], 'anydeck-ios');
    server.config = server.config.copyWith(disabledPlatforms: {'ios'});
    expect((await call('ios', 'tools/list')).$1, 503);
  });
  test('任意路径不执行请求，现代 GET 不建立旧 SSE 会话', () async {
    final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port/wrong'));
    final response = await req.close();
    expect(response.statusCode, 404);
    await response.drain<void>();
    final get = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/mcp/ios'),
    );
    get.headers.set('authorization', 'Bearer i-token');
    final res = await get.close();
    expect(res.statusCode, 405);
    await res.drain<void>();
  });
  test('凭据轮换立即撤销旧 Token，兼容入口默认关闭且迁移保留旧设置', () async {
    server.config = server.config.copyWith(
      platformTokens: {'ios': 'new-token'},
    );
    expect((await call('ios', 'tools/list')).$1, 401);
    expect((await call('ios', 'tools/list', token: 'new-token')).$1, 200);
    final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/sse'));
    final res = await req.close();
    expect(res.statusCode, 404);
    await res.drain<void>();
    expect(const McpServerConfig().enableLegacy, false);
    expect(McpServerConfig.fromJson({'port': 8765}).enableLegacy, true);
    final restored = McpServerConfig.fromJson(server.config.toJson());
    expect(restored.platformTokens, {'ios': 'new-token'});
    expect(restored.enableLegacy, false);
  });
  test('截图经 image content 返回，结构化字段不包含 Base64 文本', () {
    final result = McpResponse.toolResult(
      id: 1,
      text: 'metadata',
      legacy: false,
      extraData: {'base64': 'abcd', 'width': 10, 'mimeType': 'image/png'},
    ).result;
    expect(result['content'].first['type'], 'image');
    expect(result['content'].first['data'], 'abcd');
    expect(result['structuredContent'].containsKey('base64'), false);
    expect(result.containsKey('data'), false);
  });
  test('同设备并发调用按顺序执行，失败释放队列', () async {
    final registry = McpToolRegistry()
      ..resolvePlatform = (_) async => 'android';
    final first = Completer<void>();
    final order = <int>[];
    registry.register(
      McpToolDefinition(
        name: 'queued',
        description: '队列验证',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'deviceId': {'type': 'string'},
            'step': {'type': 'integer'},
          },
        },
        handler: (args) async {
          final step = args['step'] as int;
          order.add(step);
          if (step == 1) {
            await first.future;
            throw StateError('expected');
          }
          return {'step': step};
        },
      ),
    );
    final one = registry.executeTool(
      name: 'queued',
      arguments: {'deviceId': 'a', 'step': 1},
    );
    final expectedFailure = expectLater(one, throwsStateError);
    final two = registry.executeTool(
      name: 'queued',
      arguments: {'deviceId': 'a', 'step': 2},
    );
    await Future<void>.delayed(Duration.zero);
    expect(order, [1]);
    first.complete();
    await expectedFailure;
    expect((await two)['step'], 2);
    expect(order, [1, 2]);
  });
}
