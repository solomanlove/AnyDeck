import '../../../core/mcp/models/mcp_audit_response_summary.dart';

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
  final McpAuditResponseSummary? responseSummary;
  final bool isFromHistory;

  McpAuditLogEntry({
    required this.id,
    required this.timestamp,
    required this.method,
    this.toolName,
    this.arguments,
    required this.isSuccess,
    this.errorMessage,
    required this.durationMs,
    this.responseSummary,
    this.isFromHistory = false,
  });

  /// 本地历史只保存摘要，脱敏后的参数详情留在当前进程内存中。
  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'method': method,
    'toolName': toolName,
    'platform': arguments?['platform'],
    'isSuccess': isSuccess,
    'durationMs': durationMs,
    if (responseSummary case final summary?)
      'responseSummary': summary.toJson(),
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
        responseSummary: switch (json['responseSummary']) {
          final Map<String, dynamic> summary =>
            McpAuditResponseSummary.fromJson(summary),
          _ => null,
        },
        isFromHistory: true,
      );

  /// 工具调用优先显示工具名，协议请求显示方法名。
  String get displayTitle => toolName ?? method;

  /// 接入平台来自服务端路由，同样适用于重启后恢复的历史。
  String? get platform => arguments?['platform'] as String?;
}
