import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/mcp_audit_log_controller.dart';

/// MCP 请求与工具调用审计日志面板
class McpAuditLogsViewer extends ConsumerWidget {
  const McpAuditLogsViewer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final logs = ref.watch(mcpAuditLogProvider);
    final controller = ref.read(mcpAuditLogProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'MCP 调用审计日志 (${logs.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (logs.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => controller.clearLogs(),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('清空日志'),
                  ),
              ],
            ),
            const Divider(height: 16),
            if (logs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32.0),
                child: Center(
                  child: Text(
                    '暂无调用记录，等待 AI 客户端发送请求...',
                    style: TextStyle(
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade400,
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: logs.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = logs[index];
                  final statusColor = item.isSuccess
                      ? const Color(0xff09c47c)
                      : Colors.redAccent;

                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      item.isSuccess ? Icons.check_circle : Icons.error,
                      color: statusColor,
                      size: 18,
                    ),
                    title: Row(
                      children: [
                        Text(
                          item.displayTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${item.durationMs}ms',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.arguments != null &&
                            item.arguments!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            '参数: ${jsonEncode(item.arguments)}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (!item.isSuccess && item.errorMessage != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '错误: ${item.errorMessage}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: Text(
                      _formatTime(item.timestamp),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? Colors.grey.shade500
                            : Colors.grey.shade400,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
