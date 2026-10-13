import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/dashboard_header_bar.dart';
import '../controller/mcp_server_controller.dart';
import 'widgets/mcp_audit_logs_viewer.dart';
import 'widgets/mcp_config_snippet_card.dart';
import 'widgets/mcp_server_status_card.dart';
import 'widgets/mcp_tools_toggle_list.dart';

/// AnyDeck AI MCP (Model Context Protocol) 服务的桌面管理控制面板
class McpDashboardTab extends ConsumerWidget {
  const McpDashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        _McpDashboardHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 20),
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
        ),
      ],
    );
  }
}

/// MCP 顶部标准标题栏
class _McpDashboardHeader extends StatelessWidget {
  const _McpDashboardHeader();

  @override
  Widget build(BuildContext context) {
    return DashboardHeaderBar(
      title: context.l10n.t('aiMcp'),
      subtitle: context.l10n.t('aiMcpDesc'),
      icon: CupertinoIcons.sparkles,
      trailing: const _McpServerStatusHeaderBadge(),
    );
  }
}

/// 标题栏右侧的 MCP 服务运行状态徽章
class _McpServerStatusHeaderBadge extends ConsumerWidget {
  const _McpServerStatusHeaderBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mcpServerProvider);
    final isRunning = state.isRunning;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final badgeColor = isRunning
        ? AppPalette.primary
        : (isDark ? Colors.grey.shade600 : Colors.grey.shade500);
    final badgeBg = isRunning
        ? AppPalette.primary.withValues(alpha: 0.12)
        : (isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04));

    final label = isRunning
        ? (context.l10n.locale.languageCode == 'zh'
            ? '运行中 (端口: ${state.config.port})'
            : 'Running (Port: ${state.config.port})')
        : (context.l10n.locale.languageCode == 'zh' ? '已停止' : 'Stopped');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
              boxShadow: isRunning
                  ? [
                      BoxShadow(
                        color: badgeColor.withValues(alpha: 0.5),
                        blurRadius: 4,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }
}
