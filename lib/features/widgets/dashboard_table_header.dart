import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Dashboard 表格通用排序图标，统一各 Tab 的排序状态视觉。
class DashboardSortIcon extends StatelessWidget {
  const DashboardSortIcon({
    super.key,
    required this.active,
    required this.ascending,
    this.unsortedIcon = CupertinoIcons.chevron_up_chevron_down,
    this.ascendingIcon = CupertinoIcons.chevron_up,
    this.descendingIcon = CupertinoIcons.chevron_down,
  });

  final bool active;
  final bool ascending;
  final IconData unsortedIcon;
  final IconData ascendingIcon;
  final IconData descendingIcon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(
        active ? (ascending ? ascendingIcon : descendingIcon) : unsortedIcon,
        size: 14,
        color: active
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
      ),
    );
  }
}

/// Dashboard 表格通用可排序表头单元格。
///
/// 支持固定宽度或 flex 布局，避免不同 Tab 重复手写 Text、InkWell、
/// sort icon、ellipsis 和对齐逻辑。
class DashboardSortableHeaderCell extends StatelessWidget {
  const DashboardSortableHeaderCell({
    super.key,
    required this.label,
    required this.onTap,
    this.width,
    this.flex,
    this.style,
    this.sortIcon,
    this.alignRight = false,
    this.height,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.borderRadius,
  }) : assert(width != null || flex != null);

  final String label;
  final VoidCallback onTap;
  final double? width;
  final int? flex;
  final TextStyle? style;
  final Widget? sortIcon;
  final bool alignRight;
  final double? height;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final cell = InkWell(
      onTap: onTap,
      borderRadius: borderRadius,
      child: Container(
        height: height,
        padding: padding,
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: alignRight
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                label,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ?sortIcon,
          ],
        ),
      ),
    );

    if (flex != null) {
      return Expanded(flex: flex!, child: cell);
    }
    return SizedBox(width: width, child: cell);
  }
}
