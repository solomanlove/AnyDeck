import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/mcp_request.dart';
import '../models/mcp_response.dart';
import 'mcp_transport_interface.dart';

/// 基于命令行标准输入输出 (Stdio) 的 MCP 传输适配器
class McpStdioTransport implements McpTransportInterface {
  StreamSubscription? _stdinSubscription;
  bool _isRunning = false;

  @override
  String get name => 'Stdio';

  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> start({
    required Future<McpResponse?> Function(McpRequest request) onRequest,
  }) async {
    if (_isRunning) return;
    _isRunning = true;

    _stdinSubscription = stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) async {
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;

        try {
          final json = jsonDecode(trimmed) as Map<String, dynamic>;
          final request = McpRequest.fromJson(json);
          final response = await onRequest(request);

          // 向 stdout 发送 JSON-RPC 响应 (通知类型无需响应)
          if (response != null) {
            stdout.writeln(jsonEncode(response.toJson()));
          }
        } catch (e) {
          final errResponse = McpResponse.error(
            id: null,
            code: McpError.parseError,
            message: 'JSON 解析异常: $e',
          );
          stdout.writeln(jsonEncode(errResponse.toJson()));
        }
      },
      onError: (err) {
        stderr.writeln('[MCP Stdio Error] $err');
      },
      onDone: () {
        stop();
      },
    );
  }

  @override
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    await _stdinSubscription?.cancel();
    _stdinSubscription = null;
  }
}
