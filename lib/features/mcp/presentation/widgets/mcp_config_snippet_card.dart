import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/widget/app_toast.dart';
import '../../controller/mcp_server_controller.dart';

/// 客户端 MCP 配置代码片段生成与一键复制卡片 (仅支持 HTTP SSE 模式)
class McpConfigSnippetCard extends ConsumerWidget {
  const McpConfigSnippetCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = ref.watch(mcpServerProvider);
    final config = state.config;

    final sseUrl = 'http://${config.host}:${config.port}/sse';

    // 生成基于 HTTP SSE 的 MCP 配置 JSON
    final sseConfig = {
      'mcpServers': {
        'anydeck': {
          'url': sseUrl,
        }
      }
    };

    final configText = const JsonEncoder.withIndent('  ').convert(sseConfig);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.code, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'AI 客户端接入配置 (HTTP SSE)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: configText));
                    AppToast.show(context, '配置代码已复制到剪贴板');
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制配置'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '在 Cursor / Antigravity / Cline / Windsurf 等支持 MCP 的 AI 客户端设置中添加如下配置，即可通过 HTTP SSE 连接 AnyDeck：',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xff090d16) : const Color(0xfff1f5f9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? const Color(0xff1e293b) : const Color(0xffe2e8f0),
                ),
              ),
              child: SelectableText(
                configText,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
