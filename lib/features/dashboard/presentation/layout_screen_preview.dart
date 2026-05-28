import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'layout_tab.dart';

/// 渲染手机屏幕截图，支持 InteractiveViewer 缩放和平移，以及旋转度数下的坐标映射。
class LayoutScreenPreview extends StatelessWidget {
  final LayoutNode rootNode;
  final ui.Image decodedImage;
  final LayoutNode? selectedNode;
  final LayoutNode? hoveredNode;
  final bool showBorders;
  final int rotationAngle;
  final TransformationController transformationController;
  final ValueChanged<LayoutNode?> onNodeSelected;
  final ValueChanged<LayoutNode?> onNodeHovered;
  final ValueChanged<Size> onViewportSizeChanged;

  const LayoutScreenPreview({
    super.key,
    required this.rootNode,
    required this.decodedImage,
    required this.selectedNode,
    required this.hoveredNode,
    required this.showBorders,
    required this.rotationAngle,
    required this.transformationController,
    required this.onNodeSelected,
    required this.onNodeHovered,
    required this.onViewportSizeChanged,
  });

  LayoutNode? _findDeepestNodeAt(LayoutNode node, Offset nativePoint) {
    final rect = node.rect;
    if (rect == null || !rect.contains(nativePoint)) {
      return null;
    }

    // 优先搜索子节点
    for (final child in node.children.reversed) {
      final found = _findDeepestNodeAt(child, nativePoint);
      if (found != null) {
        return found;
      }
    }

    return node;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final viewportHeight = constraints.maxHeight;
        if (viewportWidth <= 0 || viewportHeight <= 0) {
          return const SizedBox.shrink();
        }

        // 通知父组件视口大小已变更，以便在操作栏计算 1:1 或重置时使用
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onViewportSizeChanged(Size(viewportWidth, viewportHeight));
        });

        final imageWidth = decodedImage.width.toDouble();
        final imageHeight = decodedImage.height.toDouble();

        // 旋转后的图片容器边界尺寸
        final rotatedW = (rotationAngle == 90 || rotationAngle == 270) ? imageHeight : imageWidth;
        final rotatedH = (rotationAngle == 90 || rotationAngle == 270) ? imageWidth : imageHeight;

        // 根据当前的旋转角度，将视口局部坐标映射回设备的原生坐标
        Offset localToNative(Offset localPoint) {
          final cx = localPoint.dx - rotatedW / 2;
          final cy = localPoint.dy - rotatedH / 2;

          // 逆旋转 (向后反转)
          final rad = -rotationAngle * pi / 180;
          final rx = cx * cos(rad) - cy * sin(rad);
          final ry = cx * sin(rad) + cy * cos(rad);

          // 移动回以左上角为基准的原生点
          return Offset(rx + imageWidth / 2, ry + imageHeight / 2);
        }

        LayoutNode? getNodeAtLocalPoint(Offset localPoint) {
          final nativePoint = localToNative(localPoint);
          return _findDeepestNodeAt(rootNode, nativePoint);
        }

        return Container(
          color: const Color(0xff181818),
          child: InteractiveViewer(
            transformationController: transformationController,
            boundaryMargin: const EdgeInsets.all(400.0),
            minScale: 0.05,
            maxScale: 10.0,
            child: Center(
              child: SizedBox(
                width: rotatedW,
                height: rotatedH,
                child: MouseRegion(
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
                    child: SizedBox.expand(
                      child: CustomPaint(
                        painter: _ScreenPreviewPainter(
                          image: decodedImage,
                          rootNode: rootNode,
                          selectedNode: selectedNode,
                          hoveredNode: hoveredNode,
                          showBorders: showBorders,
                          rotationAngle: rotationAngle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScreenPreviewPainter extends CustomPainter {
  final ui.Image image;
  final LayoutNode rootNode;
  final LayoutNode? selectedNode;
  final LayoutNode? hoveredNode;
  final bool showBorders;
  final int rotationAngle;

  _ScreenPreviewPainter({
    required this.image,
    required this.rootNode,
    required this.selectedNode,
    required this.hoveredNode,
    required this.showBorders,
    required this.rotationAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();

    final rotatedW = (rotationAngle == 90 || rotationAngle == 270) ? imageHeight : imageWidth;
    final rotatedH = (rotationAngle == 90 || rotationAngle == 270) ? imageWidth : imageHeight;

    canvas.save();
    // 旋转 canvas 以便我们可以使用原始的设备坐标系进行绘制
    canvas.translate(rotatedW / 2, rotatedH / 2);
    canvas.rotate(rotationAngle * pi / 180);
    canvas.translate(-imageWidth / 2, -imageHeight / 2);

    // 1. 绘制截图
    final src = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
    final dst = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
    canvas.drawImageRect(image, src, dst, Paint());

    // 2. 绘制全局布局边界
    if (showBorders) {
      final boundsPaint = Paint()
        ..color = const Color(0xff4caf50).withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      void drawAllNodeBounds(LayoutNode node) {
        final rect = node.rect;
        if (rect != null) {
          canvas.drawRect(rect, boundsPaint);
        }
        for (final child in node.children) {
          drawAllNodeBounds(child);
        }
      }

      drawAllNodeBounds(rootNode);
    }

    // 3. 绘制 Hover 节点
    if (hoveredNode != null && hoveredNode != selectedNode) {
      final rect = hoveredNode!.rect;
      if (rect != null) {
        canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.orange.withValues(alpha: 0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
        canvas.drawRect(
          rect,
          Paint()..color = Colors.orange.withValues(alpha: 0.08),
        );
      }
    }

    // 4. 绘制 Selected 选区高亮
    if (selectedNode != null) {
      final rect = selectedNode!.rect;
      if (rect != null) {
        canvas.drawRect(
          rect,
          Paint()
            ..color = const Color(0xff09c47c)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0,
        );
        canvas.drawRect(
          rect,
          Paint()..color = const Color(0xff09c47c).withValues(alpha: 0.15),
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScreenPreviewPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.rootNode != rootNode ||
        oldDelegate.selectedNode != selectedNode ||
        oldDelegate.hoveredNode != hoveredNode ||
        oldDelegate.showBorders != showBorders ||
        oldDelegate.rotationAngle != rotationAngle;
  }
}
