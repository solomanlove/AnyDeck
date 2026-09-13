import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';

/// TCP/IP 连接帮助；在连接表单下使用 const TcpipConnectionGuide()。
/// 无业务参数，文案与颜色随当前语言和主题变化；仅展示说明，不执行命令。
class TcpipConnectionGuide extends StatelessWidget {
  const TcpipConnectionGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.t('tcpipGuideTitle'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.t('tcpipGuideIntro'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        for (final step in ['Prepare', 'Enable', 'Connect', 'Verify'])
          _GuideSection(prefix: 'tcpip$step', hasCommand: true),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: Text(
            context.l10n.t('tcpipTroubleshootTitle'),
            style: theme.textTheme.titleSmall,
          ),
          children: const [
            _GuideSection(prefix: 'tcpipMultiple', hasCommand: true),
            _GuideSection(prefix: 'tcpipFailure'),
            _GuideSection(prefix: 'tcpipReconnect'),
            _GuideSection(prefix: 'tcpipDisconnect', hasCommand: true),
            _GuideSection(prefix: 'tcpipPairing'),
          ],
        ),
      ],
    );
  }
}

/// 以统一样式展示说明段落；命令可选择复制，颜色适配明暗主题。
class _GuideSection extends StatelessWidget {
  const _GuideSection({required this.prefix, this.hasCommand = false});

  final String prefix;
  final bool hasCommand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.t('${prefix}Title'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.t('${prefix}Body'),
            style: theme.textTheme.bodySmall,
          ),
          if (hasCommand) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                context.l10n.t('${prefix}Command'),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
