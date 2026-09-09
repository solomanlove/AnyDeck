import 'dart:async';
import 'dart:convert';

import 'models/mcp_request.dart';
import 'models/mcp_response.dart';
import 'models/mcp_server_config.dart';
import 'registry/mcp_tool_registry.dart';
import 'transport/mcp_sse_transport.dart';
import 'transport/mcp_stdio_transport.dart';
import 'transport/mcp_transport_interface.dart';

/// MCP 审计回调函数签名
typedef McpAuditLogCallback = void Function({
  required String method,
  required String? toolName,
  required Map<String, dynamic>? arguments,
  required bool isSuccess,
  required String? errorMessage,
  required int durationMs,
});

/// AnyDeck MCP (Model Context Protocol) 服务端核心引擎
class McpServer {
  final McpToolRegistry registry;
  McpServerConfig config;
  final McpAuditLogCallback? onAuditLog;

  McpTransportInterface? _activeTransport;
  bool _isStarted = false;

  McpServer({
    required this.registry,
    this.config = const McpServerConfig(),
    this.onAuditLog,
  });

  /// 服务端是否已启动
  bool get isStarted => _isStarted;

  /// 当前使用的传输通道名称
  String get transportName => _activeTransport?.name ?? 'None';

  /// 启动 MCP Server (默认启动 SSE 传输)
  Future<void> startSse({McpServerConfig? customConfig}) async {
    if (_isStarted) {
      await stop();
    }
    if (customConfig != null) {
      config = customConfig;
    }

    final transport = McpSseTransport(
      host: config.host,
      port: config.port,
      enableAuth: config.enableAuth,
      authToken: config.authToken,
    );

    await transport.start(onRequest: handleRequest);
    _activeTransport = transport;
    _isStarted = true;
  }

  /// 以 Stdio 命令行模式启动
  Future<void> startStdio() async {
    if (_isStarted) {
      await stop();
    }

    final transport = McpStdioTransport();
    await transport.start(onRequest: handleRequest);
    _activeTransport = transport;
    _isStarted = true;
  }

  /// 停止 MCP Server
  Future<void> stop() async {
    await _activeTransport?.stop();
    _activeTransport = null;
    _isStarted = false;
  }

  /// 核心 JSON-RPC 2.0 请求路由分发器
  Future<McpResponse> handleRequest(McpRequest request) async {
    final startTime = DateTime.now();
    String? toolName;
    Map<String, dynamic>? arguments;

    try {
      switch (request.method) {
        // 1. 协议初始化握手
        case 'initialize':
          return _handleInitialize(request);

        // 2. 客户端完成初始化通知
        case 'notifications/initialized':
          return McpResponse.success(id: request.id, result: {});

        // 3. 心跳检测
        case 'ping':
          return McpResponse.success(id: request.id, result: {});

        // 4. 获取支持的工具列表
        case 'tools/list':
          return _handleToolsList(request);

        // 5. 执行具体工具调用
        case 'tools/call':
          final params = request.params ?? {};
          toolName = params['name'] as String?;
          arguments = params['arguments'] is Map<String, dynamic>
              ? params['arguments'] as Map<String, dynamic>
              : {};

          if (toolName == null || toolName.isEmpty) {
            throw ArgumentError('tools/call 缺少 name 参数');
          }

          final executionResult = await registry.executeTool(
            name: toolName,
            arguments: arguments,
            enableDangerousGuard: config.enableDangerousOperationGuard,
            disabledTools: config.disabledToolNames,
          );

          final duration = DateTime.now().difference(startTime).inMilliseconds;
          onAuditLog?.call(
            method: request.method,
            toolName: toolName,
            arguments: arguments,
            isSuccess: true,
            errorMessage: null,
            durationMs: duration,
          );

          return McpResponse.toolResult(
            id: request.id,
            text: jsonEncode(executionResult),
            extraData: executionResult,
          );

        // 6. Resources 与 Prompts 占位
        case 'resources/list':
          return McpResponse.success(id: request.id, result: {'resources': []});

        case 'prompts/list':
          return McpResponse.success(id: request.id, result: {'prompts': []});

        default:
          return McpResponse.error(
            id: request.id,
            code: McpError.methodNotFound,
            message: '未知的 MCP 方法: ${request.method}',
          );
      }
    } catch (e) {
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      onAuditLog?.call(
        method: request.method,
        toolName: toolName,
        arguments: arguments,
        isSuccess: false,
        errorMessage: e.toString(),
        durationMs: duration,
      );

      return McpResponse.error(
        id: request.id,
        code: McpError.toolExecutionError,
        message: e.toString(),
      );
    }
  }

  /// 处理 initialize 初始化握手
  McpResponse _handleInitialize(McpRequest request) {
    return McpResponse.success(
      id: request.id,
      result: {
        'protocolVersion': '2024-11-05',
        'serverInfo': {
          'name': 'AnyDeck MCP Server',
          'version': '1.0.0',
        },
        'capabilities': {
          'tools': {'listChanged': true},
          'resources': {'subscribe': false, 'listChanged': false},
          'prompts': {'listChanged': false},
          'logging': {},
        },
      },
    );
  }

  /// 处理 tools/list
  McpResponse _handleToolsList(McpRequest request) {
    final toolsSchema = registry.toMcpToolsSchema(
      disabledTools: config.disabledToolNames,
    );
    return McpResponse.success(
      id: request.id,
      result: {'tools': toolsSchema},
    );
  }
}
