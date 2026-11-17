import 'package:any_deck/core/mcp/mcp_server.dart';
import 'package:any_deck/core/mcp/models/mcp_request.dart';
import 'package:any_deck/core/mcp/models/mcp_tool_definition.dart';
import 'package:any_deck/core/mcp/registry/mcp_tool_registry.dart';
import 'package:any_deck/features/mcp/models/mcp_audit_log_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 审计必须依据最终响应记录一次，且不能影响工具执行结果。
void main() {
  late McpServer server;
  late List<McpAuditLogEntry> logs;
  late int executions;

  setUp(() {
    logs = [];
    executions = 0;
    final registry = McpToolRegistry()
      ..register(
        McpToolDefinition(
          name: 'test_tool',
          description: '审计回归工具',
          inputSchema: const {
            'type': 'object',
            'properties': {
              'text': {'type': 'string'},
            },
          },
          handler: (_) async {
            executions++;
            return {'success': false};
          },
        ),
      );
    server = McpServer(
      registry: registry,
      onAuditLog:
          ({
            required method,
            required toolName,
            required arguments,
            required isSuccess,
            required errorMessage,
            required durationMs,
          }) {
            logs.add(
              McpAuditLogEntry(
                id: '${logs.length}',
                timestamp: DateTime.now(),
                method: method,
                toolName: toolName,
                arguments: arguments,
                isSuccess: isSuccess,
                errorMessage: errorMessage,
                durationMs: durationMs,
              ),
            );
          },
    );
  });

  for (final method in [
    'initialize',
    'server/discover',
    'tools/list',
    'unknown/method',
  ]) {
    test('$method 按最终响应记录一次审计', () async {
      final response = await server.handleRequest(
        McpRequest(id: 1, method: method),
      );
      expect(logs, hasLength(1));
      expect(logs.single.method, method);
      expect(logs.single.isSuccess, response!.error == null);
      expect(logs.single.durationMs, greaterThanOrEqualTo(0));
    });
  }

  test('工具返回业务失败时审计保留失败状态并脱敏输入', () async {
    final response = await server.handleRequest(
      const McpRequest(
        id: 1,
        method: 'tools/call',
        params: {
          'name': 'test_tool',
          'arguments': {'text': 'private-input'},
        },
      ),
    );
    expect(response!.result['isError'], true);
    expect(executions, 1);
    expect(logs, hasLength(1));
    expect(logs.single.isSuccess, false);
    expect(logs.single.errorMessage, isNotNull);
    expect(logs.single.arguments, {'platform': 'all', 'text': '[redacted]'});
  });

  test('审计观察者抛错不替换工具响应或重复执行工具', () async {
    final brokenObserver = McpServer(
      registry: server.registry,
      onAuditLog:
          ({
            required method,
            required toolName,
            required arguments,
            required isSuccess,
            required errorMessage,
            required durationMs,
          }) {
            throw StateError('storage unavailable');
          },
    );
    final response = await brokenObserver.handleRequest(
      const McpRequest(
        id: 1,
        method: 'tools/call',
        params: {'name': 'test_tool', 'arguments': <String, dynamic>{}},
      ),
    );
    expect(response!.error, isNull);
    expect(response.result['structuredContent'], {'success': false});
    expect(executions, 1);
  });

  test('通知与心跳不挤占审计历史', () async {
    expect(
      await server.handleRequest(
        const McpRequest(id: null, method: 'notifications/initialized'),
      ),
      isNull,
    );
    expect(
      (await server.handleRequest(
        const McpRequest(id: 1, method: 'ping'),
      ))!.error,
      isNull,
    );
    expect(logs, isEmpty);
  });
}
