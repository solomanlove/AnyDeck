import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../../core/layout_inspector/layout_node.dart';

/// 渲染手机屏幕截图，支持 InteractiveViewer 缩放和平移，以及旋转度数下的坐标映射。
class LayoutScreenPreview extends StatefulWidget {
  final LayoutNode? rootNode;
  final ui.Image decodedImage;
  final LayoutNode? selectedNode;
  final LayoutNode? hoveredNode;
  final bool showBorders;
  final int rotationAngle;
  final TransformationController transformationController;
  final ValueChanged<LayoutNode?> onNodeSelected;
  final ValueChanged<LayoutNode?> onNodeHovered;
  final ValueChanged<Size> onViewportSizeChanged;
  final bool enableClickSelect;
  final bool useDp;
  final double deviceScale;

  const LayoutScreenPreview({
    super.key,
    this.rootNode,
    required this.decodedImage,
    required this.selectedNode,
    required this.hoveredNode,
    required this.showBorders,
    required this.rotationAngle,
    required this.transformationController,
    required this.onNodeSelected,
    required this.onNodeHovered,
    required this.onViewportSizeChanged,
    required this.enableClickSelect,
    required this.useDp,
    required this.deviceScale,
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
    if (rect != null && !rect.contains(nativePoint)) {
      return null;
    }

    // 优先搜索子节点
    for (final child in node.children.reversed) {
      final found = _findDeepestNodeAt(child, nativePoint);
      if (found != null) {
        return found;
      }
    }

    return rect != null ? node : null;
  }

  void _resetZoomAndPan(Size viewportSize) {
    final imageWidth = widget.decodedImage.width.toDouble();
    final imageHeight = widget.decodedImage.height.toDouble();
    final rotatedW = (widget.rotationAngle == 90 || widget.rotationAngle == 270)
        ? imageHeight
        : imageWidth;
    final rotatedH = (widget.rotationAngle == 90 || widget.rotationAngle == 270)
        ? imageWidth
        : imageHeight;

    final scale = min(
      viewportSize.width / rotatedW,
      viewportSize.height / rotatedH,
    );
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
        final rotatedW =
            (widget.rotationAngle == 90 || widget.rotationAngle == 270)
            ? imageHeight
            : imageWidth;
        final rotatedH =
            (widget.rotationAngle == 90 || widget.rotationAngle == 270)
            ? imageWidth
            : imageHeight;

        final fitScale = min(
          viewportWidth / rotatedW,
          viewportHeight / rotatedH,
        );

        final minScaleVal = min(max(0.01, fitScale * 0.8), 1.0);

        final marginX = max(
          400.0,
          (viewportWidth / minScaleVal - rotatedW) / 2,
        );
        final marginY = max(
          400.0,
          (viewportHeight / minScaleVal - rotatedH) / 2,
        );

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
          if (widget.rootNode == null) return null;
          final nativePoint = localToNative(localPoint);
          return _findDeepestNodeAt(widget.rootNode!, nativePoint);
        }

        return Container(
          color: Colors.transparent,
          child: InteractiveViewer(
            transformationController: widget.transformationController,
            boundaryMargin: EdgeInsets.symmetric(
              horizontal: marginX,
              vertical: marginY,
            ),
            minScale: minScaleVal,
            maxScale: 10.0,
            constrained: false,
            child: SizedBox(
              width: rotatedW,
              height: rotatedH,
              child: MouseRegion(
                cursor: widget.enableClickSelect
                    ? SystemMouseCursors.click
                    : MouseCursor.defer,
                onHover: (event) {
                  if (!widget.enableClickSelect) return;
                  final RenderBox viewportBox =
                      context.findRenderObject() as RenderBox;
                  final viewportPoint = viewportBox.globalToLocal(
                    event.position,
                  );
                  final localPoint = widget.transformationController.toScene(
                    viewportPoint,
                  );
                  final node = getNodeAtLocalPoint(localPoint);
                  widget.onNodeHovered(node);
                },
                onExit: (_) {
                  if (!widget.enableClickSelect) return;
                  widget.onNodeHovered(null);
                },
                child: GestureDetector(
                  onTapDown: (details) {
                    if (!widget.enableClickSelect) return;
                    final RenderBox viewportBox =
                        context.findRenderObject() as RenderBox;
                    final viewportPoint = viewportBox.globalToLocal(
                      details.globalPosition,
                    );
                    final localPoint = widget.transformationController.toScene(
                      viewportPoint,
                    );
                    final nativePoint = localToNative(localPoint);
                    final node = widget.rootNode == null
                        ? null
                        : _findDeepestNodeAt(widget.rootNode!, nativePoint);
                    widget.onNodeSelected(node);

                    final x = nativePoint.dx.round();
                    final y = nativePoint.dy.round();

                    // 将坐标与选中节点信息转换为开发日志输出
                    final nodeInfo = node != null
                        ? 'Node: ${node.className} (id: ${node.resourceId}, bounds: ${node.bounds})'
                        : 'No node selected';
                    debugPrint(
                      'Layout Inspector - Clicked native coordinates: ($x, $y) - $nodeInfo',
                    );
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
                        useDp: widget.useDp,
                        deviceScale: widget.deviceScale,
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
  final LayoutNode? rootNode;
  final LayoutNode? selectedNode;
  final LayoutNode? hoveredNode;
  final bool showBorders;
  final int rotationAngle;
  final bool useDp;
  final double deviceScale;

  _ScreenPreviewPainter({
    required this.image,
    required this.rootNode,
    required this.selectedNode,
    required this.hoveredNode,
    required this.showBorders,
    required this.rotationAngle,
    required this.useDp,
    required this.deviceScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();

    final rotatedW = (rotationAngle == 90 || rotationAngle == 270)
        ? imageHeight
        : imageWidth;
    final rotatedH = (rotationAngle == 90 || rotationAngle == 270)
        ? imageWidth
        : imageHeight;

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
    if (showBorders && rootNode != null) {
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

      drawAllNodeBounds(rootNode!);
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
          Paint()..color = const Color(0xff09c47c).withValues(alpha: 0.20),
        );
      }
    }

    // 5. 绘制 Selected 与 Hovered 节点之间的几何间距
    if (selectedNode != null &&
        hoveredNode != null &&
        hoveredNode != selectedNode) {
      final r1 = selectedNode!.rect;
      final r2 = hoveredNode!.rect;
      if (r1 != null && r2 != null) {
        // 检查包含/嵌套关系 (Nested Relationship)
        final isR1InsideR2 =
            r2.contains(r1.topLeft) && r2.contains(r1.bottomRight);
        final isR2InsideR1 =
            r1.contains(r2.topLeft) && r1.contains(r2.bottomRight);

        if (isR1InsideR2 || isR2InsideR1) {
          // ==================== 内边距 (Internal Spacing) ====================
          // 选用蓝绿色/青色 (Cyan/Teal)
          const spacingColor = Color(0xff00bcd4);
          final rOuter = isR1InsideR2 ? r2 : r1;
          final rInner = isR1InsideR2 ? r1 : r2;

          // 左内间距
          final leftVal = rInner.left - rOuter.left;
          if (leftVal > 0) {
            _drawMeasurementLine(
              canvas: canvas,
              p1: Offset(rOuter.left, rInner.top + rInner.height / 2),
              p2: Offset(rInner.left, rInner.top + rInner.height / 2),
              value: leftVal,
              color: spacingColor,
            );
          }
          // 右内间距
          final rightVal = rOuter.right - rInner.right;
          if (rightVal > 0) {
            _drawMeasurementLine(
              canvas: canvas,
              p1: Offset(rInner.right, rInner.top + rInner.height / 2),
              p2: Offset(rOuter.right, rInner.top + rInner.height / 2),
              value: rightVal,
              color: spacingColor,
            );
          }
          // 上内间距
          final topVal = rInner.top - rOuter.top;
          if (topVal > 0) {
            _drawMeasurementLine(
              canvas: canvas,
              p1: Offset(rInner.left + rInner.width / 2, rOuter.top),
              p2: Offset(rInner.left + rInner.width / 2, rInner.top),
              value: topVal,
              color: spacingColor,
            );
          }
          // 下内间距
          final bottomVal = rOuter.bottom - rInner.bottom;
          if (bottomVal > 0) {
            _drawMeasurementLine(
              canvas: canvas,
              p1: Offset(rInner.left + rInner.width / 2, rInner.bottom),
              p2: Offset(rInner.left + rInner.width / 2, rOuter.bottom),
              value: bottomVal,
              color: spacingColor,
            );
          }
        } else {
          // ==================== 外边距 (External Spacing) ====================
          // 选用橙色 (Orange/Amber)
          const spacingColor = Color(0xfffb8c00);

          // 1. 水平外间距计算与绘制
          if (r1.right <= r2.left) {
            // A 在 B 左侧
            final hVal = r2.left - r1.right;
            final topBound = max(r1.top, r2.top);
            final bottomBound = min(r1.bottom, r2.bottom);
            if (topBound < bottomBound) {
              final midY = (topBound + bottomBound) / 2;
              _drawMeasurementLine(
                canvas: canvas,
                p1: Offset(r1.right, midY),
                p2: Offset(r2.left, midY),
                value: hVal,
                color: spacingColor,
              );
            } else {
              // 垂直方向无交集，绘制水平测量线与虚线引导线
              final midY1 = r1.top + r1.height / 2;
              _drawMeasurementLine(
                canvas: canvas,
                p1: Offset(r1.right, midY1),
                p2: Offset(r2.left, midY1),
                value: hVal,
                color: spacingColor,
              );
              final borderPaint = Paint()
                ..color = spacingColor.withValues(alpha: 0.4)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.0;
              canvas.drawLine(
                Offset(r2.left, midY1),
                Offset(r2.left, midY1 < r2.top ? r2.top : r2.bottom),
                borderPaint,
              );
            }
          } else if (r2.right <= r1.left) {
            // B 在 A 左侧
            final hVal = r1.left - r2.right;
            final topBound = max(r1.top, r2.top);
            final bottomBound = min(r1.bottom, r2.bottom);
            if (topBound < bottomBound) {
              final midY = (topBound + bottomBound) / 2;
              _drawMeasurementLine(
                canvas: canvas,
                p1: Offset(r2.right, midY),
                p2: Offset(r1.left, midY),
                value: hVal,
                color: spacingColor,
              );
            } else {
              final midY1 = r1.top + r1.height / 2;
              _drawMeasurementLine(
                canvas: canvas,
                p1: Offset(r2.right, midY1),
                p2: Offset(r1.left, midY1),
                value: hVal,
                color: spacingColor,
              );
              final borderPaint = Paint()
                ..color = spacingColor.withValues(alpha: 0.4)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.0;
              canvas.drawLine(
                Offset(r2.right, midY1),
                Offset(r2.right, midY1 < r2.top ? r2.top : r2.bottom),
                borderPaint,
              );
            }
          }

          // 2. 垂直外间距计算与绘制
          if (r1.bottom <= r2.top) {
            // A 在 B 上方
            final vVal = r2.top - r1.bottom;
            final leftBound = max(r1.left, r2.left);
            final rightBound = min(r1.right, r2.right);
            if (leftBound < rightBound) {
              final midX = (leftBound + rightBound) / 2;
              _drawMeasurementLine(
                canvas: canvas,
                p1: Offset(midX, r1.bottom),
                p2: Offset(midX, r2.top),
                value: vVal,
                color: spacingColor,
              );
            } else {
              // 水平方向无交集，绘制垂直测量线与虚线引导线
              final midX1 = r1.left + r1.width / 2;
              _drawMeasurementLine(
                canvas: canvas,
                p1: Offset(midX1, r1.bottom),
                p2: Offset(midX1, r2.top),
                value: vVal,
                color: spacingColor,
              );
              final borderPaint = Paint()
                ..color = spacingColor.withValues(alpha: 0.4)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.0;
              canvas.drawLine(
                Offset(midX1, r2.top),
                Offset(midX1 < r2.left ? r2.left : r2.right, r2.top),
                borderPaint,
              );
            }
          } else if (r2.bottom <= r1.top) {
            // B 在 A 上方
            final vVal = r1.top - r2.bottom;
            final leftBound = max(r1.left, r2.left);
            final rightBound = min(r1.right, r2.right);
            if (leftBound < rightBound) {
              final midX = (leftBound + rightBound) / 2;
              _drawMeasurementLine(
                canvas: canvas,
                p1: Offset(midX, r2.bottom),
                p2: Offset(midX, r1.top),
                value: vVal,
                color: spacingColor,
              );
            } else {
              final midX1 = r1.left + r1.width / 2;
              _drawMeasurementLine(
                canvas: canvas,
                p1: Offset(midX1, r2.bottom),
                p2: Offset(midX1, r1.top),
                value: vVal,
                color: spacingColor,
              );
              final borderPaint = Paint()
                ..color = spacingColor.withValues(alpha: 0.4)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.0;
              canvas.drawLine(
                Offset(midX1, r2.bottom),
                Offset(midX1 < r2.left ? r2.left : r2.right, r2.bottom),
                borderPaint,
              );
            }
          }
        }
      }
    }

    canvas.restore();
  }

  /// 辅助方法：绘制带端点刻度、数值气泡的测量标尺线
  void _drawMeasurementLine({
    required Canvas canvas,
    required Offset p1,
    required Offset p2,
    required double value,
    required Color color,
  }) {
    if (value <= 0) return;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // 绘制主体测量线
    canvas.drawLine(p1, p2, linePaint);

    // 计算切向以绘制工字端点刻度
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len > 0) {
      final ux = dx / len;
      final uy = dy / len;
      // 垂向向量
      final px = -uy;
      final py = ux;

      const tickLen = 4.0; // 单侧长 4.0，总跨度 8.0
      canvas.drawLine(
        Offset(p1.dx - px * tickLen, p1.dy - py * tickLen),
        Offset(p1.dx + px * tickLen, p1.dy + py * tickLen),
        linePaint,
      );
      canvas.drawLine(
        Offset(p2.dx - px * tickLen, p2.dy - py * tickLen),
        Offset(p2.dx + px * tickLen, p2.dy + py * tickLen),
        linePaint,
      );
    }

    final displayValue = useDp ? value / deviceScale : value;
    final unit = useDp ? 'dp' : 'px';
    final text = useDp
        ? displayValue.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')
        : displayValue.round().toString();

    // 绘制数值文本与气泡框背景
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$text $unit',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final center = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
    final textRect = Rect.fromCenter(
      center: center,
      width: textPainter.width + 10,
      height: textPainter.height + 6,
    );

    // 绘制气泡背景
    canvas.drawRRect(
      RRect.fromRectAndRadius(textRect, const Radius.circular(4)),
      Paint()..color = color,
    );

    // 绘制文本居中
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _ScreenPreviewPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.rootNode != rootNode ||
        oldDelegate.selectedNode != selectedNode ||
        oldDelegate.hoveredNode != hoveredNode ||
        oldDelegate.showBorders != showBorders ||
        oldDelegate.rotationAngle != rotationAngle ||
        oldDelegate.useDp != useDp ||
        oldDelegate.deviceScale != deviceScale;
  }
}
