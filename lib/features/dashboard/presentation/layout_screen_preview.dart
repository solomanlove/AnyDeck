import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'layout_tab.dart';

/// 渲染手机屏幕截图，支持 InteractiveViewer 缩放和平移，以及旋转度数下的坐标映射。
class LayoutScreenPreview extends StatefulWidget {
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

  @override
  State<LayoutScreenPreview> createState() => _LayoutScreenPreviewState();
}

class _LayoutScreenPreviewState extends State<LayoutScreenPreview> {
  Size? _lastSize;
  ui.Image? _lastImage;
  int? _lastRotation;

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

  void _resetZoomAndPan(Size viewportSize) {
    final imageWidth = widget.decodedImage.width.toDouble();
    final imageHeight = widget.decodedImage.height.toDouble();
    final rotatedW = (widget.rotationAngle == 90 || widget.rotationAngle == 270) ? imageHeight : imageWidth;
    final rotatedH = (widget.rotationAngle == 90 || widget.rotationAngle == 270) ? imageWidth : imageHeight;

    final scale = min(viewportSize.width / rotatedW, viewportSize.height / rotatedH);
    final renderedW = rotatedW * scale;
    final renderedH = rotatedH * scale;
    final offsetX = (viewportSize.width - renderedW) / 2;
    final offsetY = (viewportSize.height - renderedH) / 2;

    widget.transformationController.value = Matrix4.identity()
      ..setTranslationRaw(offsetX, offsetY, 0.0)
      // ignore: deprecated_member_use
      ..scale(scale);

    // 同步给父组件最新的视口大小
    widget.onViewportSizeChanged(viewportSize);
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

        final currentSize = Size(viewportWidth, viewportHeight);

        // 如果视口尺寸、图片或旋转角度发生变更，自动执行初始化居中重置，解决“第一次图片未居中”的异步时序问题
        if (_lastSize != currentSize ||
            _lastImage != widget.decodedImage ||
            _lastRotation != widget.rotationAngle) {
          _lastSize = currentSize;
          _lastImage = widget.decodedImage;
          _lastRotation = widget.rotationAngle;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _resetZoomAndPan(currentSize);
            }
          });
        }

        final imageWidth = widget.decodedImage.width.toDouble();
        final imageHeight = widget.decodedImage.height.toDouble();

        // 旋转后的图片容器边界尺寸
        final rotatedW = (widget.rotationAngle == 90 || widget.rotationAngle == 270) ? imageHeight : imageWidth;
        final rotatedH = (widget.rotationAngle == 90 || widget.rotationAngle == 270) ? imageWidth : imageHeight;

        // 根据当前的旋转角度，将视口局部坐标映射回设备的原生坐标
        Offset localToNative(Offset localPoint) {
          final cx = localPoint.dx - rotatedW / 2;
          final cy = localPoint.dy - rotatedH / 2;

          // 逆旋转 (向后反转)
          final rad = -widget.rotationAngle * pi / 180;
          final rx = cx * cos(rad) - cy * sin(rad);
          final ry = cx * sin(rad) + cy * cos(rad);

          // 移动回以左上角为基准的原生点
          return Offset(rx + imageWidth / 2, ry + imageHeight / 2);
        }

        LayoutNode? getNodeAtLocalPoint(Offset localPoint) {
          final nativePoint = localToNative(localPoint);
          return _findDeepestNodeAt(widget.rootNode, nativePoint);
        }

        return Container(
          color: const Color(0xff181818),
          child: InteractiveViewer(
            transformationController: widget.transformationController,
            boundaryMargin: const EdgeInsets.all(400.0),
            minScale: 0.05,
            maxScale: 10.0,
            constrained: false,
            child: SizedBox(
              width: rotatedW,
              height: rotatedH,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onHover: (event) {
                  final node = getNodeAtLocalPoint(event.localPosition);
                  widget.onNodeHovered(node);
                },
                onExit: (_) {
                  widget.onNodeHovered(null);
                },
                child: GestureDetector(
                  onTapDown: (details) {
                    final node = getNodeAtLocalPoint(details.localPosition);
                    widget.onNodeSelected(node);
                  },
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: _ScreenPreviewPainter(
                        image: widget.decodedImage,
                        rootNode: widget.rootNode,
                        selectedNode: widget.selectedNode,
                        hoveredNode: widget.hoveredNode,
                        showBorders: widget.showBorders,
                        rotationAngle: widget.rotationAngle,
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
