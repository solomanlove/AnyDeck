import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mcp_audit_log_entry.dart';
import '../data/mcp_audit_log_store.dart';

/// MCP 审计调用日志 Notifier
class McpAuditLogNotifier extends Notifier<List<McpAuditLogEntry>> {
  final _store = McpAuditLogStore();
  late Future<void> _ready;
  Future<void> _saving = Future.value();
  bool _clearedDuringLoad = false;

  @override
  List<McpAuditLogEntry> build() {
    _ready = Future.microtask(_restore);
    return [];
  }

  /// Server 接收请求前恢复历史；页面是否打开不影响审计生命周期。
  Future<void> get ready => _ready;

  Future<void> _restore() async {
    final history = await _store.load();
    if (!ref.mounted || _clearedDuringLoad) return;
    state = [...state, ...history].take(McpAuditLogStore.maxLogs).toList();
  }

  /// 等待最近一批写入，供停止服务和回归测试确认落盘。
  Future<void> flush() => _saving;

  void _persist() {
    _saving = _saveAfterRestore();
    unawaited(_saving);
  }

  Future<void> _saveAfterRestore() async {
    await _ready;
    if (!ref.mounted) return;
    try {
      await _store.save(state);
    } catch (error) {
      // 存储故障不能把已完成的设备调用变成失败响应。
      developer.log('MCP audit save failed: ${error.runtimeType}', name: 'mcp');
    }
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

    state = [entry, ...state].take(McpAuditLogStore.maxLogs).toList();
    _persist();
  }

  /// 清空所有调用日志
  void clearLogs() {
    _clearedDuringLoad = true;
    state = [];
    _persist();
  }
}

/// MCP 审计调用日志全局 Provider
final mcpAuditLogProvider =
    NotifierProvider<McpAuditLogNotifier, List<McpAuditLogEntry>>(
  McpAuditLogNotifier.new,
);
