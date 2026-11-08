import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 带文字的公共导航项，统一圆角、选中背景、字重与点击反馈。
///
/// [icon] 与 [label] 描述目的地；[selected] 表示选中或强调；[onTap] 为空时禁用。
/// [foregroundColor] 允许主侧栏保留状态色；[trailing] 可放置连接状态指示。
/// 外部负责列表间距及 Tooltip，主侧栏和设置分类可直接复用。
class AppNavigationItem extends StatelessWidget {
  const AppNavigationItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.foregroundColor,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final Color? foregroundColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        foregroundColor ??
        (onTap == null
            ? theme.navigationDisabledForeground
            : selected
            ? theme.colorScheme.primary
            : theme.navigationForeground);
    const radius = AppThemeSizes.radiusNavigation;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected
            ? theme.navigationSelectedBackground
            : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            height: 44,
            padding: const EdgeInsets.only(left: 10),
            child: Row(
              children: [
                Icon(icon, size: 24, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: color,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
