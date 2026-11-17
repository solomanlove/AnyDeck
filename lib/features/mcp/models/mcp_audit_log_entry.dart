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

  /// 本地历史只保存摘要，原始参数始终只留在当前进程内存中。
  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'method': method,
    'toolName': toolName,
    'platform': arguments?['platform'],
    'isSuccess': isSuccess,
    'durationMs': durationMs,
  };

  factory McpAuditLogEntry.fromJson(Map<String, dynamic> json) =>
      McpAuditLogEntry(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        method: json['method'] as String,
        toolName: json['toolName'] as String?,
        arguments: json['platform'] is String
            ? {'platform': json['platform']}
            : null,
        isSuccess: json['isSuccess'] as bool,
        durationMs: json['durationMs'] as int,
      );

  /// 转换为格式化显示文本
  String get displayTitle {
    if (method == 'tools/call' && toolName != null) {
      return 'Tool: $toolName';
    }
    return method;
  }
}
