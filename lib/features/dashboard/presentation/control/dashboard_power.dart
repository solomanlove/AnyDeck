part of '../dashboard_screen.dart';

class _PowerPanel extends ConsumerWidget {
  const _PowerPanel({required this.device});

  final AdbDevice device;

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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.t('powerTitle'),
              style: theme.textTheme.titleMedium,
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
                final double itemWidth = (constraints.maxWidth - 32) / 3;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: itemWidth,
                      child: _PowerButton(
                        icon: CupertinoIcons.refresh,
                        label: context.l10n.t('reboot'),
                        tooltip: context.l10n.t('rebootTooltip'),
                        onPressed: () => _handleReboot(context, ref, actions, null, context.l10n.t('reboot')),
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _PowerButton(
                        icon: CupertinoIcons.wrench,
                        label: context.l10n.t('rebootRecovery'),
                        tooltip: context.l10n.t('rebootRecoveryTooltip'),
                        onPressed: () => _handleReboot(context, ref, actions, 'recovery', context.l10n.t('rebootRecovery')),
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _PowerButton(
                        icon: Icons.memory,
                        label: context.l10n.t('rebootBootloader'),
                        tooltip: context.l10n.t('rebootBootloaderTooltip'),
                        onPressed: () => _handleReboot(context, ref, actions, 'bootloader', context.l10n.t('rebootBootloader')),
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _PowerButton(
                        icon: CupertinoIcons.arrow_down_circle,
                        label: context.l10n.t('rebootSideload'),
                        tooltip: context.l10n.t('rebootSideloadTooltip'),
                        onPressed: () => _handleReboot(context, ref, actions, 'sideload', context.l10n.t('rebootSideload')),
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _PowerButton(
                        icon: CupertinoIcons.arrow_down_circle,
                        label: context.l10n.t('rebootSideloadAutoReboot'),
                        tooltip: context.l10n.t('rebootSideloadAutoRebootTooltip'),
                        onPressed: () => _handleReboot(
                          context,
                          ref,
                          actions,
                          'sideload-auto-reboot',
                          context.l10n.t('rebootSideloadAutoReboot'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
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
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : const Color(0xfff3f4f6);
    final foregroundColor = theme.colorScheme.onSurface;

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
            height: 100,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 28, color: foregroundColor),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: foregroundColor,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
