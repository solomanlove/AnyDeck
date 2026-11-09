import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../app/widget/app_toast.dart';

/// 开发者模式控制区，订阅模式状态并复用现有持久化、跨窗口广播和反馈。
/// 放置在页面介绍旁；关闭后当前页面可继续操作，设置入口按原有规则隐藏。
class DeveloperModeControl extends ConsumerWidget {
  const DeveloperModeControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      appSettingsProvider.select((settings) => settings.developerModeEnabled),
    );
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      key: const ValueKey('developer-mode-control'),
      decoration: BoxDecoration(
        color: enabled ? colors.primaryContainer : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.developer_mode_rounded,
              size: 18,
              color: enabled
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                context.l10n.t('developerModeSwitch'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: enabled ? colors.onPrimaryContainer : colors.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(
              value: enabled,
              onChanged: (value) {
                ref
                    .read(appSettingsProvider.notifier)
                    .setDeveloperModeEnabled(value);
                AppToast.show(
                  context,
                  context.l10n.t(
                    value
                        ? 'developerOptionsEnabledTip'
                        : 'developerModeDisabledTip',
                  ),
                  type: value ? AppToastType.success : AppToastType.info,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
