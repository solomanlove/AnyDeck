import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import 'developer_mode_control.dart';

/// 开发者页面介绍与模式开关；宽屏在同一行右侧展示开关，窄屏换行防止溢出。
/// 不承载窗口导航，放在主体滚动区域的第一项。
class DeveloperPageHeader extends StatelessWidget {
  const DeveloperPageHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final introduction = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            CupertinoIcons.wrench_fill,
            color: colors.onPrimaryContainer,
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    context.l10n.t('developerOptions'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: Text(
                        context.l10n.t('developerLabsBadge'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.t('developerPageSubtitle'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          key: const ValueKey('developer-page-header'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: constraints.maxWidth >= 680
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: introduction),
                    const SizedBox(width: 24),
                    const DeveloperModeControl(),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    introduction,
                    const SizedBox(height: 16),
                    const DeveloperModeControl(),
                  ],
                ),
        );
      },
    );
  }
}
