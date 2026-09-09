/// MCP 请求调用审计日志条目
class McpAuditLogEntry {
  final String id;
  final DateTime timestamp;
  final String method;
  final String? toolName;
  final Map<String, dynamic>? arguments;
  final bool isSuccess;
  final String? errorMessage;
  final int durationMs;

  McpAuditLogEntry({
    required this.id,
    required this.timestamp,
    required this.method,
    this.toolName,
    this.arguments,
    required this.isSuccess,
    this.errorMessage,
    required this.durationMs,
  });

  /// 转换为格式化显示文本
  String get displayTitle {
    if (method == 'tools/call' && toolName != null) {
      return 'Tool: $toolName';
    }
    return method;
  }
}
