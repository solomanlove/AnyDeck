import 'dart:convert';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/mcp_audit_log_controller.dart';
import '../../models/mcp_audit_log_entry.dart';

/// 显示 MCP 审计历史。点击日志行可查看该次调用的详情。
class McpAuditLogsViewer extends ConsumerWidget {
  const McpAuditLogsViewer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final logs = ref.watch(mcpAuditLogProvider);

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
                Expanded(
                  child: Text(
                    '${l10n.t('mcpAuditTitle')} (${logs.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (logs.isNotEmpty)
                  TextButton.icon(
                    onPressed: () =>
                        ref.read(mcpAuditLogProvider.notifier).clearLogs(),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(l10n.t('mcpAuditClear')),
                  ),
              ],
            ),
            const Divider(height: 16),
            if (logs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32.0),
                child: Center(
                  child: Text(
                    l10n.t('mcpAuditEmpty'),
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: logs.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) => _McpAuditLogTile(logs[index]),
              ),
          ],
        ),
      ),
    );
  }
}

/// 概要行只读取轻量字段，打开详情时再格式化参数。
class _McpAuditLogTile extends StatelessWidget {
  const _McpAuditLogTile(this.entry);

  final McpAuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final status = l10n.t(
      entry.isSuccess ? 'mcpAuditSuccess' : 'mcpAuditFailure',
    );

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        entry.isSuccess ? Icons.check_circle : Icons.error,
        size: 18,
        color: entry.isSuccess
            ? theme.appColors.success
            : theme.colorScheme.error,
        semanticLabel: status,
      ),
      title: Text(
        entry.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      subtitle: Wrap(
        spacing: 12,
        children: [
          if (entry.platform case final platform?) Text(platform),
          Text(_formatTime(entry.timestamp.toLocal())),
          Text('${entry.durationMs} ms'),
        ],
      ),
      trailing: Tooltip(
        message: l10n.t('mcpAuditDetails'),
        child: const Icon(Icons.chevron_right),
      ),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => _McpAuditLogDetails(entry),
      ),
    );
  }
}

/// 详情绑定点击时的记录，后续请求抵达时仍可阅读和复制该条数据。
class _McpAuditLogDetails extends StatelessWidget {
  const _McpAuditLogDetails(this.entry);

  final McpAuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final summary = entry.responseSummary;
    final timestamp = entry.timestamp.toLocal();
    final arguments = {
      for (final argument
          in entry.arguments?.entries ?? const <MapEntry<String, dynamic>>[])
        if (argument.key != 'platform') argument.key: argument.value,
    };

    return AlertDialog(
      title: Text(l10n.t('mcpAuditDetails')),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(l10n.t('mcpAuditMethod'), entry.method),
              if (entry.toolName case final toolName?)
                _field(l10n.t('mcpAuditTool'), toolName),
              if (entry.platform case final platform?)
                _field(l10n.t('mcpAuditPlatform'), platform),
              _field(
                l10n.t('mcpAuditTimestamp'),
                '${MaterialLocalizations.of(context).formatCompactDate(timestamp)} '
                '${_formatTime(timestamp)}',
              ),
              _field(l10n.t('mcpAuditDuration'), '${entry.durationMs} ms'),
              _field(
                l10n.t('mcpAuditStatus'),
                l10n.t(entry.isSuccess ? 'mcpAuditSuccess' : 'mcpAuditFailure'),
              ),
              if (summary != null) ...[
                _field(l10n.t('mcpAuditProtocol'), summary.protocolVersion),
                if (summary.supportedVersions.isNotEmpty)
                  _field(
                    l10n.t('mcpAuditSupportedVersions'),
                    summary.supportedVersions.join(', '),
                  ),
                if (summary.itemCount case final count?)
                  _field(l10n.t('mcpAuditItemCount'), count.toString()),
                if (summary.errorCode case final code?)
                  _field(l10n.t('mcpAuditErrorCode'), code.toString()),
              ],
              if (summary?.isToolError == true)
                Text(
                  l10n.t('mcpAuditToolError'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              if (arguments.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.t('mcpAuditArguments'),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  const JsonEncoder.withIndent('  ').convert(arguments),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              if (entry.isFromHistory) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.t('mcpAuditHistory'),
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('close')),
        ),
      ],
    );
  }

  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: value),
        ],
      ),
    ),
  );
}

/// 保留秒级时间，便于和设备端日志对齐。
String _formatTime(DateTime timestamp) => [
  timestamp.hour,
  timestamp.minute,
  timestamp.second,
].map((value) => value.toString().padLeft(2, '0')).join(':');
