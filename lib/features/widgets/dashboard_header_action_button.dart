import 'package:flutter/material.dart';

/// 标题栏普通操作按钮，统一图标尺寸、点击区域及圆角水波纹。
///
/// [icon] 为操作图标；[tooltip] 使用调用方的本地化文案；
/// [color] 传入所在工具栏的主题前景色；[onPressed] 为空时禁用。
/// 用法：`DashboardHeaderActionButton(icon: Icon(Icons.refresh),
/// tooltip: label, color: toolbarColor, onPressed: refresh)`。
class DashboardHeaderActionButton extends StatelessWidget {
  const DashboardHeaderActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final Widget icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: icon,
      iconSize: 30,
      color: color,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        fixedSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
