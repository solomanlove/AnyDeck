import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widgets/mcp_audit_logs_viewer.dart';
import 'widgets/mcp_config_snippet_card.dart';
import 'widgets/mcp_server_status_card.dart';
import 'widgets/mcp_tools_toggle_list.dart';

/// AnyDeck AI MCP (Model Context Protocol) 服务的桌面管理控制面板
class McpDashboardTab extends ConsumerWidget {
  const McpDashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    const brandGreen = Color(0xff09c47c);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部标题：MCP 服务
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: brandGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: brandGreen,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MCP 服务',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Model Context Protocol 开放服务，支持 CodeX / Claude 等 AI 客户端直连控制',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            const McpServerStatusCard(),
            const SizedBox(height: 16),
            const McpConfigSnippetCard(),
            const SizedBox(height: 16),
            const McpToolsToggleList(),
            const SizedBox(height: 16),
            const McpAuditLogsViewer(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
