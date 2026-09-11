import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../../core/layout_inspector/layout_node.dart';

/// 屏幕截图与布局分析共享绘制器。
/// 在普通截图模式下仅绘制带旋转和缩放的截图底图；
/// 在布局分析模式下额外绘制全量绿色组件边框、Hover 橙色高亮、选中绿色高亮及两两之间的测量标尺线。
class ScreenPreviewPainter extends CustomPainter {
  final ui.Image image;
  final LayoutNode? rootNode;
  final LayoutNode? selectedNode;
  final LayoutNode? hoveredNode;
  final bool showBorders;
  final int rotationAngle;
  final bool useDp;
  final double deviceScale;

  ScreenPreviewPainter({
    required this.image,
    this.rootNode,
    this.selectedNode,
    this.hoveredNode,
    this.showBorders = false,
    required this.rotationAngle,
    this.useDp = true,
    this.deviceScale = 1.0,
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

    // 1. 绘制截图底图
    final src = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
    final dst = Rect.fromLTWH(0, 0, imageWidth, imageHeight);
    canvas.drawImageRect(image, src, dst, Paint());

    // 2. 绘制全局布局边界（开启显示边框且存在节点树时）
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

    // 5. 绘制 Selected 与 Hovered 节点之间的几何间距测量线
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
          // 内边距 (Internal Spacing)
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
          // 外边距 (External Spacing)
          const spacingColor = Color(0xfffb8c00);

          // 1. 水平外间距计算与绘制
          if (r1.right <= r2.left) {
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

  /// 绘制带端点刻度与数值气泡的测量标尺线
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
      final px = -uy;
      final py = ux;

      const tickLen = 4.0;
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

    // 绘制居中文本
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant ScreenPreviewPainter oldDelegate) {
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
