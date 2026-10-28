import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 控制台 Toolbar 的统一 Icon 操作，选中态使用主题主色表达开关状态。
///
/// [tooltip] 为本地化说明；[icon] 为动作图标；[onPressed] 执行动作；
/// [selected] 表示筛选或显示开关已启用。独立窗口与底部 Toolbar 共用。
class ConsoleToolbarButton extends StatelessWidget {
  const ConsoleToolbarButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      style: consoleToolbarButtonStyle(theme, selected: selected),
      icon: Icon(icon, size: 18),
      selectedIcon: Icon(icon, size: 18),
      onPressed: onPressed,
    );
  }
}

ButtonStyle consoleToolbarButtonStyle(
  ThemeData theme, {
  bool selected = false,
}) {
  return IconButton.styleFrom(
    minimumSize: const Size.square(36),
    maximumSize: const Size.square(36),
    padding: EdgeInsets.zero,
    foregroundColor: selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant,
    backgroundColor: selected
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : theme.appColors.subtleSurface,
    side: BorderSide(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.35)
          : theme.colorScheme.outlineVariant,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: AppThemeSizes.radiusMedium,
    ),
  );
}
