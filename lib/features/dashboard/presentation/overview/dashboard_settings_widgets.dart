part of '../dashboard_screen.dart';

extension _SettingsTabWidgets on _SettingsTab {
  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return _GlassSectionCard(
      title: title,
      icon: icon,
      children: children,
    );
  }

  Widget _buildSettingRow(
    BuildContext context, {
    required String label,
    required String subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              textColumn,
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: child,
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: textColumn),
            const SizedBox(width: 16),
            Flexible(
              flex: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOptionButton(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const brandGreen = Color(0xff09c47c);
    final outlineColor = selected
        ? brandGreen
        : (isDark ? const Color(0xff334155) : const Color(0xffe2e8f0));
    final textColor = selected
        ? brandGreen
        : (isDark ? Colors.white70 : const Color(0xff5f6b6e));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? brandGreen.withValues(alpha: 0.1)
                : Colors.transparent,
            border: Border.all(color: outlineColor, width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: textColor),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
