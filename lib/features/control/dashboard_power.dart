part of '../dashboard_screen.dart';

/// 按卡片可用宽度排列电源操作，触发前统一确认目标模式。
class _PowerPanel extends ConsumerWidget {
  const _PowerPanel({required this.device});

  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(deviceActionServiceProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Responsive Warning banner styling
    final warningBg = isDark
        ? Colors.orange.withValues(alpha: 0.15)
        : const Color(0xfffff3cd);
    final warningBorder = isDark
        ? Colors.orange.withValues(alpha: 0.3)
        : const Color(0xffffeeba);
    final warningText = isDark
        ? const Color(0xfffbbd08)
        : const Color(0xff856404);

    final isOnline = ref.watch(deviceOnlineProvider(device.id));

    // 将普通卡片背景替换为与主页一致的毛玻璃卡片背景
    return _GlassSectionCard(
      title: context.l10n.t('powerTitle'),
      icon: CupertinoIcons.power,
      children: [
        Text(
          context.l10n.t('powerTitle'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: warningBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: warningBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.exclamationmark_triangle_fill,
                    color: isDark ? const Color(0xfffbbd08) : Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.t('powerWarning'),
                      style: TextStyle(
                        color: warningText,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 8.0;
                // 保留长模式名称的阅读宽度，剩余空间由同一行的按钮均分。
                final columns = ((constraints.maxWidth + gap) / (180 + gap))
                    .floor()
                    .clamp(1, 3);
                final itemWidth = (constraints.maxWidth - (columns - 1) * gap) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    SizedBox(
                      width: itemWidth,
                      child: _PowerButton(
                        icon: CupertinoIcons.refresh,
                        label: context.l10n.t('reboot'),
                        tooltip: context.l10n.t('rebootTooltip'),
                        onPressed: isOnline ? () => _handleReboot(
                          context,
                          ref,
                          actions,
                          null,
                          context.l10n.t('reboot'),
                        ) : null,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _PowerButton(
                        icon: CupertinoIcons.wrench,
                        label: context.l10n.t('rebootRecovery'),
                        tooltip: context.l10n.t('rebootRecoveryTooltip'),
                        onPressed: isOnline ? () => _handleReboot(
                          context,
                          ref,
                          actions,
                          'recovery',
                          context.l10n.t('rebootRecovery'),
                        ) : null,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _PowerButton(
                        icon: Icons.memory,
                        label: context.l10n.t('rebootBootloader'),
                        tooltip: context.l10n.t('rebootBootloaderTooltip'),
                        onPressed: isOnline ? () => _handleReboot(
                          context,
                          ref,
                          actions,
                          'bootloader',
                          context.l10n.t('rebootBootloader'),
                        ) : null,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _PowerButton(
                        icon: CupertinoIcons.arrow_down_circle,
                        label: context.l10n.t('rebootSideload'),
                        tooltip: context.l10n.t('rebootSideloadTooltip'),
                        onPressed: isOnline ? () => _handleReboot(
                          context,
                          ref,
                          actions,
                          'sideload',
                          context.l10n.t('rebootSideload'),
                        ) : null,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _PowerButton(
                        icon: CupertinoIcons.arrow_down_circle,
                        label: context.l10n.t('rebootSideloadAutoReboot'),
                        tooltip: context.l10n.t(
                          'rebootSideloadAutoRebootTooltip',
                        ),
                        onPressed: isOnline ? () => _handleReboot(
                          context,
                          ref,
                          actions,
                          'sideload-auto-reboot',
                          context.l10n.t('rebootSideloadAutoReboot'),
                        ) : null,
                      ),
                    ),
                  ],
                );
              },
            ),
      ],
    );
  }

  Future<void> _handleReboot(
    BuildContext context,
    WidgetRef ref,
    DeviceActionService actions,
    String? mode,
    String modeLabel,
  ) async {
    final confirmMsg = context.l10n
        .t('rebootConfirmTo')
        .replaceAll('{mode}', modeLabel);
    final confirmed = await _confirm(context, confirmMsg);
    if (confirmed && context.mounted) {
      await _runAdbAction(context, ref, actions.reboot(device.id, mode));
    }
  }
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : const Color(0xfff3f4f6);
    final foregroundColor = onPressed == null
        ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
        : theme.colorScheme.onSurface;

    return Tooltip(
      message: tooltip,
      preferBelow: true,
      waitDuration: const Duration(milliseconds: 300),
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: foregroundColor),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: foregroundColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
