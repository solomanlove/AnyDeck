import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controller/mcp_server_controller.dart';

/// MCP 服务状态控制与配置卡片
class McpServerStatusCard extends ConsumerWidget {
  const McpServerStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = ref.watch(mcpServerProvider);
    final controller = ref.read(mcpServerProvider.notifier);

    final statusColor = state.isRunning ? const Color(0xff09c47c) : Colors.grey;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: state.isRunning
                        ? [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.5),
                              blurRadius: 6,
                              spreadRadius: 2,
                            )
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'MCP Server 服务状态',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {
                    if (state.isRunning) {
                      controller.stopServer();
                    } else {
                      controller.startServer();
                    }
                  },
                  icon: Icon(
                    state.isRunning ? Icons.stop : Icons.play_arrow,
                    size: 18,
                  ),
                  label: Text(state.isRunning ? '停止服务' : '启动服务'),
                  style: FilledButton.styleFrom(
                    backgroundColor: state.isRunning
                        ? Colors.red.shade600
                        : const Color(0xff09c47c),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '状态: ${state.statusText}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
              ),
            ),
            if (state.lastError != null) ...[
              const SizedBox(height: 6),
              Text(
                '异常信息: ${state.lastError}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const Divider(height: 24),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text('监听地址: '),
                    SizedBox(
                      width: 140,
                      height: 36,
                      child: TextField(
                        textAlign: TextAlign.center,
                        textAlignVertical: TextAlignVertical.center,
                        controller: TextEditingController(text: state.config.host),
                        decoration: const InputDecoration(
                          hintText: '127.0.0.1',
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          isDense: true,
                        ),
                        onSubmitted: (val) {
                          final newConfig = state.config.copyWith(host: val.trim());
                          controller.updateConfig(newConfig);
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text('端口: '),
                    SizedBox(
                      width: 90,
                      height: 36,
                      child: TextField(
                        textAlign: TextAlign.center,
                        textAlignVertical: TextAlignVertical.center,
                        controller: TextEditingController(text: '${state.config.port}'),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '8765',
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          isDense: true,
                        ),
                        onSubmitted: (val) {
                          final port = int.tryParse(val.trim());
                          if (port != null && port > 0 && port < 65536) {
                            final newConfig = state.config.copyWith(port: port);
                            controller.updateConfig(newConfig);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('高危命令防护拦截'),
                    const SizedBox(width: 8),
                    Switch.adaptive(
                      value: state.config.enableDangerousOperationGuard,
                      activeThumbColor: const Color(0xff09c47c),
                      activeTrackColor: const Color(0xff09c47c).withValues(alpha: 0.5),
                      onChanged: (val) {
                        final newConfig = state.config.copyWith(
                          enableDangerousOperationGuard: val,
                        );
                        controller.updateConfig(newConfig);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
