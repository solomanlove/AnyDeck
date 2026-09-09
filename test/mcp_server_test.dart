import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/mcp/mcp_server.dart';
import 'package:any_deck/core/mcp/models/mcp_request.dart';
import 'package:any_deck/core/mcp/models/mcp_response.dart';
import 'package:any_deck/core/mcp/models/mcp_tool_definition.dart';
import 'package:any_deck/core/mcp/registry/mcp_tool_registry.dart';
import 'package:any_deck/core/mcp/security/mcp_security_guard.dart';

void main() {
  group('McpSecurityGuard Tests', () {
    test('拦截高危 rm -rf / 命令', () {
      final reason = McpSecurityGuard.checkDangerousShellCommand('rm -rf /');
      expect(reason, isNotNull);
      expect(reason, contains('安全拦截'));
    });

    test('放行安全的常规 Shell 命令', () {
      final reason = McpSecurityGuard.checkDangerousShellCommand('getprop ro.build.version.release');
      expect(reason, isNull);
    });

    test('拦截已被禁用的工具', () {
      final reason = McpSecurityGuard.checkToolExecutionAllowed(
        toolName: 'execute_shell',
        isDangerous: true,
        enableDangerousGuard: true,
        disabledTools: {'execute_shell'},
      );
      expect(reason, isNotNull);
      expect(reason, contains('已在 AnyDeck 设置中被禁用'));
    });
  });

  group('McpServer & Registry Protocol Tests', () {
    late McpToolRegistry registry;
    late McpServer server;

    setUp(() {
      registry = McpToolRegistry();
      // 注册模拟测试工具
      registry.register(
        McpToolDefinition(
          name: 'echo_test',
          description: '测试回显工具',
          inputSchema: {
            'type': 'object',
            'required': ['message'],
            'properties': {
              'message': {'type': 'string'},
            },
          },
          handler: (args) async {
            return {'echo': args['message']};
          },
        ),
      );

      server = McpServer(registry: registry);
    });

    test('测试 initialize 协议握手', () async {
      final req = McpRequest(
        id: 'req-1',
        method: 'initialize',
        params: {
          'protocolVersion': '2024-11-05',
          'clientInfo': {'name': 'test-client', 'version': '1.0'},
        },
      );

      final res = await server.handleRequest(req);
      expect(res, isNotNull);
      expect(res!.id, equals('req-1'));
      expect(res.error, isNull);
      expect(res.result['protocolVersion'], equals('2024-11-05'));
      expect(res.result['serverInfo']['name'], equals('anydeck'));
    });

    test('测试 notifications/initialized 通知不返回任何响应', () async {
      final req = const McpRequest(
        id: null,
        method: 'notifications/initialized',
      );

      final res = await server.handleRequest(req);
      expect(res, isNull);
    });

    test('测试 tools/list 列表查询', () async {
      final req = const McpRequest(
        id: 'req-2',
        method: 'tools/list',
      );

      final res = await server.handleRequest(req);
      expect(res, isNotNull);
      expect(res!.error, isNull);
      final tools = res.result['tools'] as List<dynamic>;
      expect(tools.length, equals(1));
      expect(tools.first['name'], equals('echo_test'));
    });

    test('测试 tools/call 成功调用工具', () async {
      final req = const McpRequest(
        id: 'req-3',
        method: 'tools/call',
        params: {
          'name': 'echo_test',
          'arguments': {'message': 'Hello MCP'},
        },
      );

      final res = await server.handleRequest(req);
      expect(res, isNotNull);
      expect(res!.error, isNull);
      expect(res.result['isError'], isFalse);
      expect(res.result['data']['echo'], equals('Hello MCP'));
    });

    test('测试未识别的 method 错误响应', () async {
      final req = const McpRequest(
        id: 'req-4',
        method: 'unknown/method',
      );

      final res = await server.handleRequest(req);
      expect(res, isNotNull);
      expect(res!.error, isNotNull);
      expect(res.error!.code, equals(McpError.methodNotFound));
    });
  });
}
