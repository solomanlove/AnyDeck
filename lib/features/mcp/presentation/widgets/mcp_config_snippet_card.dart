import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/l10n/app_localizations.dart';
import '../../../../app/widget/app_toast.dart';
import '../../controller/mcp_server_controller.dart';

/// 三个平台独立接入配置。复制按钮包含凭据，页面不展示凭据明文。
/// 从 [mcpServerProvider] 获取配置和回调；自适应开关显式跟随主题主色。
class McpConfigSnippetCard extends ConsumerWidget {
  const McpConfigSnippetCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final state = ref.watch(mcpServerProvider);
    final controller = ref.read(mcpServerProvider.notifier);
    final base = 'http://${state.config.host}:${state.config.port}';
    Future<void> copy(String platform) async {
      final config = {
        'mcpServers': {
          platform == 'all' ? 'anydeck' : 'anydeck-$platform': {
            'url': platform == 'all' ? '$base/sse' : '$base/mcp/$platform',
            if (platform != 'all')
              'headers': {
                'Authorization':
                    'Bearer ${state.config.platformTokens[platform]}',
              },
            if (platform == 'all' && state.config.enableAuth)
              'headers': {'Authorization': 'Bearer ${state.config.authToken}'},
          },
        },
      };
      await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(config)),
      );
      if (context.mounted) AppToast.show(context, context.l10n.t('mcpCopied'));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.t('mcpPlatformTitle'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(context.l10n.t('mcpPlatformDesc')),
            for (final entry in const {
              'android': 'Android_MCP',
              'harmony': 'HarmonyOS_MCP',
              'ios': 'iOS_MCP',
            }.entries)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.value,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    SelectableText('$base/mcp/${entry.key}'),
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Switch.adaptive(
                          activeThumbColor: colors.onPrimary,
                          activeTrackColor: colors.primary,
                          value: !state.config.disabledPlatforms.contains(
                            entry.key,
                          ),
                          onChanged: (v) =>
                              controller.setPlatformEnabled(entry.key, v),
                        ),
                        Text(context.l10n.t('mcpEndpointEnabled')),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.copy, size: 16),
                          label: Text(context.l10n.t('mcpCopyConfig')),
                          onPressed:
                              state
                                      .config
                                      .platformTokens[entry.key]
                                      ?.isNotEmpty ==
                                  true
                              ? () => copy(entry.key)
                              : null,
                        ),
                        TextButton(
                          onPressed: () async {
                            await controller.rotatePlatformToken(entry.key);
                            if (context.mounted) {
                              AppToast.show(
                                context,
                                context.l10n.t('mcpRotateDone'),
                              );
                            }
                          },
                          child: Text(context.l10n.t('mcpRotateToken')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const Divider(height: 24),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: colors.onPrimary,
              activeTrackColor: colors.primary,
              title: Text(context.l10n.t('mcpLegacyEnabled')),
              value: state.config.enableLegacy,
              onChanged: (v) => controller.updateConfig(
                state.config.copyWith(enableLegacy: v),
              ),
            ),
            TextButton(
              onPressed: state.config.enableLegacy ? () => copy('all') : null,
              child: Text(context.l10n.t('mcpLegacy')),
            ),
          ],
        ),
      ),
    );
  }
}
