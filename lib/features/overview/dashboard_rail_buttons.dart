part of '../dashboard_screen.dart';

// 导航项、折叠菜单与按钮样式共享，保持宽窄侧边栏交互一致。

class _RailToolItem {
  const _RailToolItem({
    required this.tabIndex,
    required this.icon,
    required this.label,
  });

  final int tabIndex;
  final IconData icon;
  final String label;
}

class _RailMoreButton extends StatelessWidget {
  const _RailMoreButton({
    required this.tools,
    required this.hasSelectedDevice,
    required this.selectedTool,
    required this.isToolEnabled,
    required this.onSelected,
    required this.isNarrow,
    this.verticalPadding,
  });

  final List<_RailToolItem> tools;
  final bool hasSelectedDevice;
  final int selectedTool;
  final bool Function(int) isToolEnabled;
  final ValueChanged<int> onSelected;
  final bool isNarrow;
  final double? verticalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final selected =
        hasSelectedDevice && tools.any((tool) => tool.tabIndex == selectedTool);

    // Ellipsis button is enabled only if at least one tool in the overflow is enabled
    final anyEnabled = tools.any((tool) => isToolEnabled(tool.tabIndex));

    final defaultColor = isDark ? const Color(0xffeceff1) : const Color(0xff455a64);
    final disabledColor = isDark ? const Color(0xff546e7a) : const Color(0xff8b9a9e);
    final color = !anyEnabled
        ? disabledColor
        : (selected ? AppPalette.primary : defaultColor);

    final activeBgColor = theme.colorScheme.primary.withValues(
      alpha: isDark ? 0.18 : 0.09,
    );

    final popupBgColor = isDark ? const Color(0xff1e222b) : const Color(0xfff5f6f8);
    final popupBorderColor = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xffeceef1);

    if (isNarrow) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: verticalPadding ?? 6),
        child: Center(
          child: PopupMenuButton<int>(
            tooltip: context.l10n.t('moreTools'),
            onSelected: anyEnabled ? onSelected : null,
            enabled: anyEnabled,
            offset: const Offset(66, 0),
            color: popupBgColor,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: popupBorderColor, width: 1),
            ),
            constraints: const BoxConstraints(minWidth: 68, maxWidth: 68),
            itemBuilder: (context) => [
              for (final tool in tools)
                PopupMenuItem<int>(
                  value: tool.tabIndex,
                  enabled: isToolEnabled(tool.tabIndex),
                  padding: EdgeInsets.zero,
                  height: 52,
                  child: Center(
                    child: Icon(
                      tool.icon,
                      size: 26,
                      color: tool.tabIndex == selectedTool
                          ? AppPalette.primary
                          : (isToolEnabled(tool.tabIndex) ? defaultColor : disabledColor),
                    ),
                  ),
                ),
            ],
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected
                    ? activeBgColor
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(CupertinoIcons.ellipsis, size: 28, color: color),
            ),
          ),
        ),
      );
    } else {
      return Padding(
        padding: EdgeInsets.symmetric(
          vertical: verticalPadding ?? 4,
          horizontal: 12,
        ),
        child: PopupMenuButton<int>(
          tooltip: context.l10n.t('moreTools'),
          onSelected: anyEnabled ? onSelected : null,
          enabled: anyEnabled,
          offset: const Offset(164, 0),
          color: popupBgColor,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: popupBorderColor, width: 1),
          ),
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 200),
          itemBuilder: (context) => [
            for (final tool in tools)
              PopupMenuItem<int>(
                value: tool.tabIndex,
                enabled: isToolEnabled(tool.tabIndex),
                height: 40,
                child: Row(
                  children: [
                    Icon(
                      tool.icon,
                      size: 20,
                      color: tool.tabIndex == selectedTool
                          ? AppPalette.primary
                          : (isToolEnabled(tool.tabIndex) ? defaultColor : disabledColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tool.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: tool.tabIndex == selectedTool
                              ? AppPalette.primary
                              : (isToolEnabled(tool.tabIndex) ? defaultColor : disabledColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: Material(
            color: selected
                ? activeBgColor
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(CupertinoIcons.ellipsis, size: 24, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.t('moreTools'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.isNarrow,
    this.selected = false,
    this.isHighlighted = false,
    this.statusColor,
    this.verticalPadding,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool isNarrow;
  final bool selected;
  final bool isHighlighted;
  final Color? statusColor;
  final double? verticalPadding;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color color;
    if (onPressed == null) {
      color = theme.navigationDisabledForeground;
    } else if (selected || isHighlighted) {
      color = AppPalette.primary;
    } else {
      color = theme.navigationForeground;
    }

    final activeBgColor = theme.navigationSelectedBackground;

    if (isNarrow) {
      return Tooltip(
        message: tooltip,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: verticalPadding ?? 6),
          child: Center(
            child: IconButton(
              icon: Badge(
                isLabelVisible: statusColor != null,
                backgroundColor: statusColor ?? Colors.transparent,
                smallSize: 8,
                child: Icon(icon, color: color),
              ),
              iconSize: 28,
              onPressed: onPressed,
              style: IconButton.styleFrom(
                fixedSize: const Size(48, 48),
                foregroundColor: color,
                backgroundColor: (selected || isHighlighted)
                    ? activeBgColor
                    : Colors.transparent,
                disabledForegroundColor: theme.navigationDisabledForeground,
                shape: RoundedRectangleBorder(
                  borderRadius: AppThemeSizes.radiusNavigation,
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      return Tooltip(
        message: tooltip,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: verticalPadding ?? 4,
            horizontal: 12,
          ),
          child: AppNavigationItem(
            icon: icon,
            label: tooltip,
            selected: selected || isHighlighted,
            foregroundColor: color,
            onTap: onPressed,
            trailing: statusColor == null
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 8),
                      _RailStatusDot(color: statusColor!),
                      const SizedBox(width: 10),
                    ],
                  ),
          ),
        ),
      );
    }
  }
}

class _RailStatusDot extends StatelessWidget {
  const _RailStatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
