import '../models/mcp_request.dart';
import '../models/mcp_response.dart';

/// MCP 传输层抽象接口
abstract class McpTransportInterface {
  /// 启动传输层监听
  Future<void> start({
    required Future<McpResponse?> Function(McpRequest request) onRequest,
  });

  /// 停止传输层并释放连接资源
  Future<void> stop();

  /// 传输层当前是否处于运行状态
  bool get isRunning;

  /// 传输通道名称 (如 "SSE", "Stdio")
  String get name;
}
