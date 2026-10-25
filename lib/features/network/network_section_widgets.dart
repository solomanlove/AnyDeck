import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/l10n/app_localizations.dart';

/// 网络页分组标题；[helpText] 非空时在 [title] 旁显示可点击的说明入口。
class NetworkSectionHeader extends StatelessWidget {
  const NetworkSectionHeader({
    super.key,
    required this.title,
    this.actions,
    this.trailingText,
    this.helpText,
  });

  final String title;
  final List<Widget>? actions;
  final String? trailingText;
  final String? helpText;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        if (helpText != null) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: context.l10n.t('portForwardHelpTooltip'),
            icon: const Icon(Icons.help_outline, size: 18),
            color: colors.onSurfaceVariant,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(title),
                content: Text(helpText!),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(dialogContext.l10n.t('close')),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (trailingText != null) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              trailingText!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const Spacer(),
        ...?actions,
      ],
    );
  }
}

/// 网络规则和预设的空状态；[icon]、[title] 与 [subtitle] 由调用方提供。
class NetworkEmptyState extends StatelessWidget {
  const NetworkEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 48),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: colors.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
