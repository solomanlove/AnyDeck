import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mcp_audit_log_entry.dart';

/// 保存最近的审计摘要；合并等待中的快照并串行写入，避免旧写入覆盖新记录。
/// 仅持久化调用元数据和平台，不把设备 ID、输入内容、路径或凭据写入磁盘。
class McpAuditLogStore {
  static const preferencesKey = 'mcp.auditLog.v1';
  static const maxLogs = 200;
  List<McpAuditLogEntry>? _pending;
  Future<void>? _writing;

  Future<List<McpAuditLogEntry>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(preferencesKey);
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .take(maxLogs)
          .map(
            (json) => McpAuditLogEntry.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (error) {
      _report(error);
      return [];
    }
  }

  Future<void> save(List<McpAuditLogEntry> logs) {
    _pending = logs.take(maxLogs).toList();
    return _writing ??= _drain().whenComplete(() => _writing = null);
  }

  Future<void> _drain() async {
    final prefs = await SharedPreferences.getInstance();
    while (_pending != null) {
      final snapshot = _pending!;
      _pending = null;
      if (!await prefs.setString(
        preferencesKey,
        jsonEncode(snapshot.map((entry) => entry.toJson()).toList()),
      )) {
        throw StateError('MCP audit storage write failed');
      }
    }
  }

  /// 审计存储异常只记录类型，不记录可能含有敏感内容的异常正文。
  static void _report(Object error) {
    developer.log(
      'MCP audit storage failed: ${error.runtimeType}',
      name: 'mcp',
    );
  }
}
