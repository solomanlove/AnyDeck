import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mcp_audit_log_entry.dart';

/// MCP 审计调用日志 Notifier
class McpAuditLogNotifier extends Notifier<List<McpAuditLogEntry>> {
  static const int _maxLogs = 200;

  @override
  List<McpAuditLogEntry> build() {
    return [];
  }

  /// 记录一条新的调用日志
  void recordLog({
    required String method,
    required String? toolName,
    required Map<String, dynamic>? arguments,
    required bool isSuccess,
    required String? errorMessage,
    required int durationMs,
  }) {
    final entry = McpAuditLogEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      method: method,
      toolName: toolName,
      arguments: arguments,
      isSuccess: isSuccess,
      errorMessage: errorMessage,
      durationMs: durationMs,
    );

    final updated = [entry, ...state];
    if (updated.length > _maxLogs) {
      state = updated.sublist(0, _maxLogs);
    } else {
      state = updated;
    }
  }

  /// 清空所有调用日志
  void clearLogs() {
    state = [];
  }
}

/// MCP 审计调用日志全局 Provider
final mcpAuditLogProvider =
    NotifierProvider<McpAuditLogNotifier, List<McpAuditLogEntry>>(
  McpAuditLogNotifier.new,
);
