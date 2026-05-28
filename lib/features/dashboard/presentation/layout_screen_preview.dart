import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'layout_tab.dart';

/// 渲染手机屏幕截图，并在其上叠加手势交互与高亮边框。
class LayoutScreenPreview extends StatelessWidget {
  final LayoutNode rootNode;
  final ui.Image decodedImage;
  final LayoutNode? selectedNode;
  final LayoutNode? hoveredNode;
  final ValueChanged<LayoutNode?> onNodeSelected;
  final ValueChanged<LayoutNode?> onNodeHovered;

  const LayoutScreenPreview({
    super.key,
    required this.rootNode,
    required this.decodedImage,
    required this.selectedNode,
    required this.hoveredNode,
    required this.onNodeSelected,
    required this.onNodeHovered,
  });

  LayoutNode? _findDeepestNodeAt(LayoutNode node, Offset nativePoint) {
    final rect = node.rect;
    if (rect == null || !rect.contains(nativePoint)) {
      return null;
    }

    // 优先搜索子节点（因为子节点在树的最深层，即界面最上层）
    for (final child in node.children.reversed) {
      final found = _findDeepestNodeAt(child, nativePoint);
      if (found != null) {
        return found;
      }
    }

    // 如果子节点都不包含该点，但当前节点包含
    return node;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xff181818), // 采用暗色背景来展示手机屏幕截图，使其更具沉浸感
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.maxWidth;
          final viewportHeight = constraints.maxHeight;
          if (viewportWidth <= 0 || viewportHeight <= 0) {
            return const SizedBox.shrink();
          }

          final imageWidth = decodedImage.width.toDouble();
          final imageHeight = decodedImage.height.toDouble();

          // 保持宽高比适配视口大小
          final scale = min(viewportWidth / imageWidth, viewportHeight / imageHeight);
          final renderedWidth = imageWidth * scale;
          final renderedHeight = imageHeight * scale;
          final offsetX = (viewportWidth - renderedWidth) / 2;
          final offsetY = (viewportHeight - renderedHeight) / 2;

          LayoutNode? getNodeAtLocalPoint(Offset localPoint) {
            final x = localPoint.dx;
            final y = localPoint.dy;

            // 检查点击或悬停点是否在图片范围内
            if (x < offsetX ||
                x > offsetX + renderedWidth ||
                y < offsetY ||
                y > offsetY + renderedHeight) {
              return null;
            }

            // 映射回设备原生坐标系
            final nativeX = (x - offsetX) / scale;
            final nativeY = (y - offsetY) / scale;

            return _findDeepestNodeAt(rootNode, Offset(nativeX, nativeY));
          }

          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onHover: (event) {
              final node = getNodeAtLocalPoint(event.localPosition);
              onNodeHovered(node);
            },
            onExit: (_) {
              onNodeHovered(null);
            },
            child: GestureDetector(
              onTapDown: (details) {
                final node = getNodeAtLocalPoint(details.localPosition);
                onNodeSelected(node);
              },
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: CustomPaint(
                  painter: _ScreenPreviewPainter(
                    image: decodedImage,
                    rootNode: rootNode,
                    selectedNode: selectedNode,
                    hoveredNode: hoveredNode,
                    scale: scale,
                    offsetX: offsetX,
                    offsetY: offsetY,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ScreenPreviewPainter extends CustomPainter {
  final ui.Image image;
  final LayoutNode rootNode;
  final LayoutNode? selectedNode;
  final LayoutNode? hoveredNode;
  final double scale;
  final double offsetX;
  final double offsetY;

  _ScreenPreviewPainter({
    required this.image,
    required this.rootNode,
    required this.selectedNode,
    required this.hoveredNode,
    required this.scale,
    required this.offsetX,
    required this.offsetY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 绘制居中的设备屏幕截图
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(offsetX, offsetY, image.width.toDouble() * scale, image.height.toDouble() * scale);
    canvas.drawImageRect(image, src, dst, Paint());

    // 2. 绘制所有节点的微弱边缘边框（辅助开发，类似于 Android 开发者选项中的“显示布局边界”）
    final boundsPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    void drawAllNodeBounds(LayoutNode node) {
      final rect = node.rect;
      if (rect != null) {
        final scaledRect = Rect.fromLTRB(
          offsetX + rect.left * scale,
          offsetY + rect.top * scale,
          offsetX + rect.right * scale,
          offsetY + rect.bottom * scale,
        );
        canvas.drawRect(scaledRect, boundsPaint);
      }
      for (final child in node.children) {
        drawAllNodeBounds(child);
      }
    }

    drawAllNodeBounds(rootNode);

    // 3. 绘制悬停状态边框（橙色细边框）
    if (hoveredNode != null && hoveredNode != selectedNode) {
      final rect = hoveredNode!.rect;
      if (rect != null) {
        final scaledRect = Rect.fromLTRB(
          offsetX + rect.left * scale,
          offsetY + rect.top * scale,
          offsetX + rect.right * scale,
          offsetY + rect.bottom * scale,
        );
        canvas.drawRect(
          scaledRect,
          Paint()
            ..color = Colors.orange.withValues(alpha: 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        canvas.drawRect(
          scaledRect,
          Paint()..color = Colors.orange.withValues(alpha: 0.08),
        );
      }
    }

    // 4. 绘制选中状态边框（品牌绿色粗边框）
    if (selectedNode != null) {
      final rect = selectedNode!.rect;
      if (rect != null) {
        final scaledRect = Rect.fromLTRB(
          offsetX + rect.left * scale,
          offsetY + rect.top * scale,
          offsetX + rect.right * scale,
          offsetY + rect.bottom * scale,
        );
        canvas.drawRect(
          scaledRect,
          Paint()
            ..color = const Color(0xff09c47c)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
        canvas.drawRect(
          scaledRect,
          Paint()..color = const Color(0xff09c47c).withValues(alpha: 0.15),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScreenPreviewPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.rootNode != rootNode ||
        oldDelegate.selectedNode != selectedNode ||
        oldDelegate.hoveredNode != hoveredNode ||
        oldDelegate.scale != scale ||
        oldDelegate.offsetX != offsetX ||
        oldDelegate.offsetY != offsetY;
  }
}
