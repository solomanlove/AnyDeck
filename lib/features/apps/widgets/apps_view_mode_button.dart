import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';

/// 应用页列表/网格视图切换按钮。
///
/// [selected] 表示当前视图，选中时使用 [AppPalette.primary] 强调 Icon；
/// [icon] 与 [selectedIcon] 分别表示普通态和选中态图标。
class AppsViewModeButton extends StatelessWidget {
  const AppsViewModeButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.selectedIcon,
  });

  final String tooltip;
  final IconData icon;
  final IconData? selectedIcon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      isSelected: selected,
      selectedIcon: Icon(
        selectedIcon ?? icon,
        size: 20,
        color: AppPalette.primary,
      ),
      onPressed: onPressed,
    );
  }
}
