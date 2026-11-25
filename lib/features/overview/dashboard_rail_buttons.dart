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
  });

  final List<_RailToolItem> tools;
  final bool hasSelectedDevice;
  final int selectedTool;
  final bool Function(int) isToolEnabled;
  final ValueChanged<int> onSelected;
  final bool isNarrow;

  static const double _verticalPadding = 2;
  static const double slotHeight =
      AppThemeSizes.navigationItemHeight + 2 * _verticalPadding;
  static const double _menuIconSize = 20;

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
        : (selected ? theme.colorScheme.primary : defaultColor);
    final moreIcon = Icon(
      CupertinoIcons.ellipsis,
      size: AppThemeSizes.navigationIconSize,
      color: color,
    );

    final activeBgColor = theme.colorScheme.primary.withValues(
      alpha: isDark ? 0.18 : 0.09,
    );

    final popupBgColor = isDark ? const Color(0xff1e222b) : const Color(0xfff5f6f8);
    final popupBorderColor = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xffeceef1);

    if (isNarrow) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: _verticalPadding),
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
                      size: _menuIconSize,
                      color: tool.tabIndex == selectedTool
                          ? theme.colorScheme.primary
                          : (isToolEnabled(tool.tabIndex) ? defaultColor : disabledColor),
                    ),
                  ),
                ),
            ],
            child: Container(
              width: AppThemeSizes.navigationItemHeight,
              height: AppThemeSizes.navigationItemHeight,
              decoration: BoxDecoration(
                color: selected
                    ? activeBgColor
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: moreIcon,
            ),
          ),
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: _verticalPadding,
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
                      size: _menuIconSize,
                      color: tool.tabIndex == selectedTool
                          ? theme.colorScheme.primary
                          : (isToolEnabled(tool.tabIndex) ? defaultColor : disabledColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tool.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: tool.tabIndex == selectedTool
                              ? theme.colorScheme.primary
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
              height: AppThemeSizes.navigationItemHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  moreIcon,
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

/// 模拟器入口按平台显示运行数量，复用侧栏通用圆点样式。
class _EmulatorRailButton extends ConsumerWidget {
  const _EmulatorRailButton({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.isNarrow,
    required this.onPressed,
  });

  final IconData icon;
  final bool selected;
  final String tooltip;
  final bool isNarrow;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(runningEmulatorCountsProvider);
    final l10n = context.l10n;
    final platforms = [
      ('navigationEmulatorAndroid', counts.android),
      ('navigationEmulatorHarmony', counts.harmony),
      ('navigationEmulatorIos', counts.ios),
    ];
    final lines = [
      for (final (platform, count) in platforms)
        if (count > 0)
          l10n
              .t(
                count == 1
                    ? 'navigationEmulatorRunningOne'
                    : 'navigationEmulatorRunningMany',
              )
              .replaceAll('{count}', '$count')
              .replaceAll('{platform}', l10n.t(platform)),
    ];
    return _RailButton(
      icon: icon,
      tooltip: tooltip,
      isNarrow: isNarrow,
      selected: selected,
      statusColor: lines.isEmpty ? null : Theme.of(context).colorScheme.primary,
      statusTooltip: lines.join('\n'),
      onPressed: onPressed,
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.isNarrow,
    this.selected = false,
    this.statusColor,
    this.statusTooltip,
    this.isFooter = false,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool isNarrow;
  final bool selected;
  final Color? statusColor;
  final String? statusTooltip;
  final bool isFooter;
  final VoidCallback? onPressed;

  static const double _footerPadding = 4;
  static const double footerSlotHeight =
      AppThemeSizes.navigationItemHeight + 2 * _footerPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color color;
    if (onPressed == null) {
      color = theme.navigationDisabledForeground;
    } else if (selected) {
      color = theme.colorScheme.primary;
    } else {
      color = theme.navigationForeground;
    }

    final activeBgColor = theme.navigationSelectedBackground;
    final verticalPadding = isFooter ? _footerPadding : (isNarrow ? 3.0 : 2.0);

    if (isNarrow) {
      return Tooltip(
        message: tooltip,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          child: Center(
            child: IconButton(
              icon: Stack(
                children: [
                  // 对称留空保持图标与圆点的位置，并让整个圆点可悬浮。
                  Padding(
                    padding: statusColor == null
                        ? EdgeInsets.zero
                        : const EdgeInsets.all(4),
                    child: Icon(icon, color: color),
                  ),
                  if (statusColor != null)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _RailStatusDot(
                        color: statusColor!,
                        message: statusTooltip,
                      ),
                    ),
                ],
              ),
              iconSize: AppThemeSizes.navigationIconSize,
              onPressed: onPressed,
              style: IconButton.styleFrom(
                fixedSize: Size.square(
                  isFooter ? AppThemeSizes.navigationItemHeight : 48,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: color,
                backgroundColor: selected
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
            vertical: verticalPadding,
            horizontal: 12,
          ),
          child: AppNavigationItem(
            icon: icon,
            label: tooltip,
            selected: selected,
            foregroundColor: color,
            onTap: onPressed,
            trailing: statusColor == null
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 8),
                      _RailStatusDot(
                        color: statusColor!,
                        message: statusTooltip,
                      ),
                      const SizedBox(width: 10),
                    ],
                  ),
          ),
        ),
      );
    }
  }
}

/// 宽窄侧栏共用的服务运行标记；不参与页面选中态。
class _RailStatusDot extends StatelessWidget {
  const _RailStatusDot({required this.color, this.message});

  final Color color;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message ?? context.l10n.t('navigationServiceRunning'),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
