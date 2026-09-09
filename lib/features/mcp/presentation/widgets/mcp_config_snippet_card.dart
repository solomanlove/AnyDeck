import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/widget/app_toast.dart';
import '../../controller/mcp_server_controller.dart';

/// 客户端 MCP 配置代码片段生成与一键复制卡片
class McpConfigSnippetCard extends ConsumerStatefulWidget {
  const McpConfigSnippetCard({super.key});

  @override
  ConsumerState<McpConfigSnippetCard> createState() => _McpConfigSnippetCardState();
}

class _McpConfigSnippetCardState extends ConsumerState<McpConfigSnippetCard> {
  int _selectedClientIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = ref.watch(mcpServerProvider);
    final config = state.config;

    final sseUrl = 'http://${config.host}:${config.port}/sse';

    // 生成配置 JSON 字符串
    final cursorConfig = {
      'mcpServers': {
        'anydeck': {
          'url': sseUrl,
        }
      }
    };

    final claudeConfig = {
      'mcpServers': {
        'anydeck': {
          'command': '/Applications/AnyDeck.app/Contents/MacOS/AnyDeck',
          'args': ['--mcp-stdio'],
        }
      }
    };

    final configText = _selectedClientIndex == 0
        ? const JsonEncoder.withIndent('  ').convert(cursorConfig)
        : const JsonEncoder.withIndent('  ').convert(claudeConfig);

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
                  'AI 客户端接入配置',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('CodeX / SSE'),
                      icon: Icon(Icons.bolt, size: 16),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('Claude / Stdio'),
                      icon: Icon(Icons.terminal, size: 16),
                    ),
                  ],
                  selected: {_selectedClientIndex},
                  onSelectionChanged: (set) {
                    setState(() {
                      _selectedClientIndex = set.first;
                    });
                  },
                ),
                const SizedBox(width: 12),
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
              _selectedClientIndex == 0
                  ? '在 CodeX / Cursor / Antigravity 的 MCP 设置中添加如下配置，即可通过 HTTP SSE 连接 AnyDeck：'
                  : '在 Claude Desktop 的 claude_desktop_config.json 中添加如下配置，即可通过 Stdio 管道拉起：',
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
