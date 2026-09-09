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
    return const Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            McpServerStatusCard(),
            SizedBox(height: 16),
            McpConfigSnippetCard(),
            SizedBox(height: 16),
            McpToolsToggleList(),
            SizedBox(height: 16),
            McpAuditLogsViewer(),
            SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
