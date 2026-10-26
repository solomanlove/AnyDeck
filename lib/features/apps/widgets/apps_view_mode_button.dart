import 'package:flutter/material.dart';

/// 应用页列表/网格视图切换按钮。
///
/// [selected] 表示当前视图，选中时使用主题绿色 Icon 和浅绿色背景；
/// [icon] 与左侧导航使用同一套线框 Icon，切换状态时不改变图标造型。
class AppsViewModeButton extends StatelessWidget {
  const AppsViewModeButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      isSelected: selected,
      selectedIcon: Icon(icon, size: 20, color: primary),
      style: IconButton.styleFrom(
        backgroundColor: selected
            ? primary.withValues(alpha: 0.12)
            : Colors.transparent,
      ),
      onPressed: onPressed,
    );
  }
}
