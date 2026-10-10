import 'package:flutter/material.dart';

/// 为图标或组件右下角添加下拉角标指示器的通用组件。
///
/// 视觉效果参考设计软件或 IDE 工具栏按钮（例如 Adobe / JetBrains 等），
/// 在图标的右下角展示一个实心小直角三角形，提示用户该操作按钮具有
/// 包含额外选项的下拉菜单或更多操作。
class MenuCornerIndicator extends StatelessWidget {
  /// 创建一个带有右下角下拉三角指示标的组件。
  ///
  /// [child] 为主图标或子组件，通常为 [Icon]。
  /// [indicatorSize] 为右下角直角三角形指示标的大小（两直角边长，默认 7.0）。
  /// [indicatorColor] 为指示标颜色，为空时自动继承当前环境中的 [IconTheme.color] 或主题前景色。
  /// [size] 为外层容器大小（宽高），为空时自动使用父级 [IconTheme.size]（回退值为 24.0）。
  /// [offset] 为三角形指示标在右下角位置的微调偏移量（默认 Offset.zero 紧贴右下角）。
  const MenuCornerIndicator({
    super.key,
    required this.child,
    this.indicatorSize = 7.0,
    this.indicatorColor,
    this.size,
    this.offset = Offset.zero,
  });

  /// 主图标或内容组件，通常为 [Icon]
  final Widget child;

  /// 右下角直角三角形指示标的大小（直角边长，默认 7.0）
  final double indicatorSize;

  /// 指示标颜色；若为 null，则自动取自父级 [IconTheme] 或主题前景色
  final Color? indicatorColor;

  /// 外层容器大小（宽高）；若为 null，则自动取自父级 [IconTheme.size]（默认为 24.0）
  final double? size;

  /// 三角形指示标在右下角位置的微调偏移量
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconTheme = IconTheme.of(context);
    final effectiveSize = size ?? iconTheme.size ?? 24.0;
    final effectiveColor = indicatorColor ??
        iconTheme.color ??
        theme.colorScheme.onSurface;

    return SizedBox(
      width: effectiveSize,
      height: effectiveSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          child,
          Positioned(
            right: offset.dx,
            bottom: offset.dy,
            width: indicatorSize,
            height: indicatorSize,
            child: CustomPaint(
              size: Size(indicatorSize, indicatorSize),
              painter: _MenuCornerTrianglePainter(color: effectiveColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// 绘制右下角实心直角三角形指示标的画笔。
///
/// 直角顶点位于右下角 (width, height)，
/// 另外两个顶点分别位于右上角 (width, 0) 与左下角 (0, height)。
class _MenuCornerTrianglePainter extends CustomPainter {
  const _MenuCornerTrianglePainter({required this.color});

  /// 三角形填充颜色
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MenuCornerTrianglePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
