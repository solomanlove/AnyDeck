import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme.dart';

/// 展示常见视频 App 的投放协议示例；最终能力以 App 当前投屏列表为准。
class ReceiverAppSupportGuide extends StatelessWidget {
  const ReceiverAppSupportGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = [
      _SupportItem(
        name: context.l10n.t('receiverExampleBilibili'),
        platforms: context.l10n.t('receiverExampleBilibiliSupport'),
        protocols: const ['DLNA', 'AirPlay'],
      ),
      _SupportItem(
        name: context.l10n.t('receiverExampleDouyin'),
        platforms: context.l10n.t('receiverExampleDouyinSupport'),
        protocols: const ['DLNA'],
      ),
      _SupportItem(
        name: context.l10n.t('receiverExampleTencentVideo'),
        platforms: context.l10n.t('receiverExampleTencentVideoSupport'),
        protocols: const ['DLNA', 'AirPlay'],
      ),
      _SupportItem(
        name: context.l10n.t('receiverExampleYangshipin'),
        platforms: context.l10n.t('receiverExampleHarmonyDlnaSupport'),
        protocols: const ['DLNA'],
      ),
      _SupportItem(
        name: context.l10n.t('receiverExampleMangoTv'),
        platforms: context.l10n.t('receiverExampleHarmonyDlnaSupport'),
        protocols: const ['DLNA'],
      ),
      _SupportItem(
        name: context.l10n.t('receiverExampleIqiyi'),
        platforms: context.l10n.t('receiverExampleVersionDependent'),
        protocols: const ['DLNA', 'AirPlay'],
      ),
      _SupportItem(
        name: context.l10n.t('receiverExampleXiaohongshu'),
        platforms: context.l10n.t('receiverExampleXiaohongshuSupport'),
        protocols: const ['DLNA'],
      ),
    ];

    return Container(
      key: const Key('receiverAppSupportGuide'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppThemeSizes.radiusLarge,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.t('receiverExamplesTitle'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.t('receiverExamplesDesc'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.appColors.mutedForeground,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 900
                  ? (constraints.maxWidth - 24) / 3
                  : constraints.maxWidth >= 560
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: items
                    .map((item) => SizedBox(width: width, child: item))
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SupportItem extends StatelessWidget {
  const _SupportItem({
    required this.name,
    required this.platforms,
    required this.protocols,
  });

  final String name;
  final String platforms;
  final List<String> protocols;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppThemeSizes.radiusMedium,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  platforms,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.appColors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 6,
            children: protocols
                .map(
                  (protocol) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      protocol,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}
