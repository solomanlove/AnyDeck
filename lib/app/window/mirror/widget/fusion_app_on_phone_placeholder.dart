import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// 应用离开融合副屏后显示的占位内容。
///
/// [appName] 和 [iconPath] 对应当前融合应用；[isRestarting] 禁用重复点击；
/// [onRestart] 将应用重新放回现有副屏。用法：叠在持续运行的投屏 Viewer 上。
class FusionAppOnPhonePlaceholder extends StatelessWidget {
  const FusionAppOnPhonePlaceholder({
    super.key,
    required this.appName,
    required this.iconPath,
    required this.isRestarting,
    required this.onRestart,
  });

  final String appName;
  final String? iconPath;
  final bool isRestarting;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasIcon = iconPath != null && File(iconPath!).existsSync();
    return ColoredBox(
      color: colors.surfaceContainerLow,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox.square(
                dimension: 80,
                child: ColoredBox(
                  color: colors.surface,
                  child: hasIcon
                      ? Image.file(File(iconPath!), fit: BoxFit.contain)
                      : Icon(
                          Icons.apps_rounded,
                          size: 44,
                          color: colors.onSurfaceVariant,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              appName,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: isRestarting ? null : onRestart,
              style: FilledButton.styleFrom(
                backgroundColor: colors.surfaceContainerHigh,
                foregroundColor: colors.onSurfaceVariant,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
              ),
              child: isRestarting
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onSurfaceVariant,
                      ),
                    )
                  : Text(context.l10n.t('fusionRestartApp')),
            ),
          ],
        ),
      ),
    );
  }
}
