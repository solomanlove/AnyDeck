import 'package:flutter/material.dart';

/// 统一图表采样数据点模型。
class ChartDataPoint {
  const ChartDataPoint({required this.value, required this.label});

  final double value; // 具体数值
  final String label; // 时间戳字符串 (如 "15:52:30")
}

/// 支持渐变填充、网格线和鼠标悬停交互的折线/面积图。
class InteractiveLineChart extends StatefulWidget {
  const InteractiveLineChart({
    super.key,
    required this.data,
    required this.maxVal,
    required this.lineColor,
    required this.fillGradientColors,
    this.unit = '%',
  });

  final List<ChartDataPoint> data;
  final double maxVal;
  final Color lineColor;
  final List<Color> fillGradientColors;
  final String unit;

  @override
  State<InteractiveLineChart> createState() => _InteractiveLineChartState();
}

class _InteractiveLineChartState extends State<InteractiveLineChart> {
  Offset? _hoverPosition;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) {
        setState(() {
          _hoverPosition = event.localPosition;
        });
      },
      onExit: (_) {
        setState(() {
          _hoverPosition = null;
        });
      },
      child: CustomPaint(
        size: Size.infinite,
        painter: _LineChartPainter(
          data: widget.data,
          maxVal: widget.maxVal,
          lineColor: widget.lineColor,
          gradientColors: widget.fillGradientColors,
          hoverPosition: _hoverPosition,
          unit: widget.unit,
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.data,
    required this.maxVal,
    required this.lineColor,
    required this.gradientColors,
    required this.hoverPosition,
    required this.unit,
  });

  final List<ChartDataPoint> data;
  final double maxVal;
  final Color lineColor;
  final List<Color> gradientColors;
  final Offset? hoverPosition;
  final String unit;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double width = size.width;
    final double height = size.height;

    // 绘制背景网格
    final gridPaint = Paint()
      ..color = const Color(0xffeceef1)
      ..strokeWidth = 1.0;

    // 水平分割线
    canvas.drawLine(Offset(0, 0), Offset(width, 0), gridPaint); // 100%
    canvas.drawLine(Offset(0, height / 2), Offset(width, height / 2), gridPaint); // 50%
    canvas.drawLine(Offset(0, height), Offset(width, height), gridPaint); // 0%

    // 纵向时间网格 (按 5 列等分)
    final colSpacing = width / 5;
    for (int i = 1; i < 5; i++) {
      canvas.drawLine(Offset(i * colSpacing, 0), Offset(i * colSpacing, height), gridPaint);
    }

    // 绘制坐标轴文字
    const textStyle = TextStyle(color: Color(0xff80868b), fontSize: 10, fontWeight: FontWeight.w500);
    _drawText(canvas, '${maxVal.toInt()}$unit', Offset(6, 4), textStyle);
    _drawText(canvas, '${(maxVal / 2).toInt()}$unit', Offset(6, height / 2 - 6), textStyle);

    // 计算折线点坐标
    final List<Offset> points = [];
    final double stepX = data.length > 1 ? width / (data.length - 1) : width;

    for (int i = 0; i < data.length; i++) {
      final val = data[i].value;
      final x = i * stepX;
      // y 轴翻转，100% 在顶端 (y=0)，0% 在底端 (y=height)
      final y = height - (val / maxVal * height);
      points.add(Offset(x, y.clamp(0.0, height)));
    }

    // 绘制面积渐变填充
    if (points.length > 1) {
      final fillPath = Path()
        ..moveTo(points.first.dx, height)
        ..lineTo(points.first.dx, points.first.dy);

      for (int i = 1; i < points.length; i++) {
        fillPath.lineTo(points[i].dx, points[i].dy);
      }
      fillPath.lineTo(points.last.dx, height);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
        ).createShader(Rect.fromLTRB(0, 0, width, height));

      canvas.drawPath(fillPath, fillPaint);
    }

    // 绘制折线
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(linePath, linePaint);

    // 如果鼠标悬停，绘制悬停指示器和 Tooltip
    if (hoverPosition != null && data.length > 1) {
      // 找出最近的样本索引
      final double hoverX = hoverPosition!.dx;
      int closestIndex = (hoverX / stepX).round();
      closestIndex = closestIndex.clamp(0, data.length - 1);

      final targetPoint = points[closestIndex];
      final targetData = data[closestIndex];

      // 1. 绘制纵向指示虚线
      final dashPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.6)
        ..strokeWidth = 1.0;

      double startY = 0;
      const dashWidth = 4.0;
      const dashSpace = 4.0;
      while (startY < height) {
        canvas.drawLine(
          Offset(targetPoint.dx, startY),
          Offset(targetPoint.dx, startY + dashWidth),
          dashPaint,
        );
        startY += dashWidth + dashSpace;
      }

      // 2. 绘制选中数据点发光圆圈
      canvas.drawCircle(targetPoint, 6.0, Paint()..color = lineColor.withValues(alpha: 0.3));
      canvas.drawCircle(targetPoint, 4.0, Paint()..color = lineColor);
      canvas.drawCircle(targetPoint, 2.0, Paint()..color = Colors.white);

      // 3. 绘制 Tooltip 箱子
      final tooltipText = '${targetData.value.toStringAsFixed(1)}$unit\n${targetData.label}';
      final textSpan = TextSpan(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          height: 1.3,
        ),
        text: tooltipText,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final tooltipW = textPainter.width + 16;
      final tooltipH = textPainter.height + 12;

      // 尽量把 Tooltip 放在悬停线左右侧，避免超出屏幕边缘
      double tooltipX = targetPoint.dx + 8;
      if (tooltipX + tooltipW > width) {
        tooltipX = targetPoint.dx - tooltipW - 8;
      }
      double tooltipY = targetPoint.dy - tooltipH / 2;
      if (tooltipY < 4) tooltipY = 4;
      if (tooltipY + tooltipH > height - 4) tooltipY = height - tooltipH - 4;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(tooltipX, tooltipY, tooltipW, tooltipH),
        const Radius.circular(6),
      );

      canvas.drawRRect(
        rect,
        Paint()
          ..color = const Color(0xff1e293b).withValues(alpha: 0.9)
          ..style = PaintingStyle.fill,
      );

      textPainter.paint(canvas, Offset(tooltipX + 8, tooltipY + 6));
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final textSpan = TextSpan(text: text, style: style);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.hoverPosition != hoverPosition ||
        oldDelegate.maxVal != maxVal ||
        oldDelegate.lineColor != lineColor;
  }
}

/// 支持渐变柱子和悬停 Tooltip 交互的柱状图 (专门针对 FPS)
class InteractiveBarChart extends StatefulWidget {
  const InteractiveBarChart({
    super.key,
    required this.data,
    required this.maxVal,
    required this.barColor,
    this.unit = '',
  });

  final List<ChartDataPoint> data;
  final double maxVal;
  final Color barColor;
  final String unit;

  @override
  State<InteractiveBarChart> createState() => _InteractiveBarChartState();
}

class _InteractiveBarChartState extends State<InteractiveBarChart> {
  Offset? _hoverPosition;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) {
        setState(() {
          _hoverPosition = event.localPosition;
        });
      },
      onExit: (_) {
        setState(() {
          _hoverPosition = null;
        });
      },
      child: CustomPaint(
        size: Size.infinite,
        painter: _BarChartPainter(
          data: widget.data,
          maxVal: widget.maxVal,
          barColor: widget.barColor,
          hoverPosition: _hoverPosition,
          unit: widget.unit,
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.data,
    required this.maxVal,
    required this.barColor,
    required this.hoverPosition,
    required this.unit,
  });

  final List<ChartDataPoint> data;
  final double maxVal;
  final Color barColor;
  final Offset? hoverPosition;
  final String unit;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double width = size.width;
    final double height = size.height;

    // 绘制背景网格
    final gridPaint = Paint()
      ..color = const Color(0xffeceef1)
      ..strokeWidth = 1.0;

    canvas.drawLine(Offset(0, 0), Offset(width, 0), gridPaint); // 60
    canvas.drawLine(Offset(0, height / 2), Offset(width, height / 2), gridPaint); // 30
    canvas.drawLine(Offset(0, height), Offset(width, height), gridPaint); // 0

    // 纵向网格
    final colSpacing = width / 5;
    for (int i = 1; i < 5; i++) {
      canvas.drawLine(Offset(i * colSpacing, 0), Offset(i * colSpacing, height), gridPaint);
    }

    // 绘制网格文字
    const textStyle = TextStyle(color: Color(0xff80868b), fontSize: 10, fontWeight: FontWeight.w500);
    _drawText(canvas, '${maxVal.toInt()}$unit', Offset(6, 4), textStyle);
    _drawText(canvas, '${(maxVal / 2).toInt()}$unit', Offset(6, height / 2 - 6), textStyle);

    // 计算柱状图宽度
    final double totalBars = data.length.toDouble();
    // 柱子之间间隔为 20%
    final double groupW = width / totalBars;
    final double barW = groupW * 0.8;
    final double spaceW = groupW * 0.2;

    int? hoveredIndex;
    if (hoverPosition != null) {
      final double hoverX = hoverPosition!.dx;
      hoveredIndex = (hoverX / groupW).floor().clamp(0, data.length - 1);
    }

    for (int i = 0; i < data.length; i++) {
      final val = data[i].value;
      final x = i * groupW + spaceW / 2;
      final y = height - (val / maxVal * height);

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(x, y.clamp(0.0, height), x + barW, height),
        const Radius.circular(2),
      );

      final isHovered = hoveredIndex == i;
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            isHovered ? barColor.withValues(alpha: 0.9) : barColor.withValues(alpha: 0.7),
            isHovered ? barColor.withValues(alpha: 0.5) : barColor.withValues(alpha: 0.3),
          ],
        ).createShader(Rect.fromLTRB(x, y.clamp(0.0, height), x + barW, height));

      canvas.drawRRect(rect, paint);
    }

    // 绘制悬停 Tooltip
    if (hoveredIndex != null) {
      final targetData = data[hoveredIndex];
      final x = hoveredIndex * groupW + spaceW / 2 + barW / 2;
      final val = targetData.value;
      final y = height - (val / maxVal * height);

      // 绘制柱子高亮圆球
      canvas.drawCircle(Offset(x, y), 4.0, Paint()..color = barColor);
      canvas.drawCircle(Offset(x, y), 2.0, Paint()..color = Colors.white);

      final tooltipText = '${targetData.value.toStringAsFixed(0)}$unit\n${targetData.label}';
      final textSpan = TextSpan(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          height: 1.3,
        ),
        text: tooltipText,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final tooltipW = textPainter.width + 16;
      final tooltipH = textPainter.height + 12;

      double tooltipX = x + 8;
      if (tooltipX + tooltipW > width) {
        tooltipX = x - tooltipW - 8;
      }
      double tooltipY = y - tooltipH / 2;
      if (tooltipY < 4) tooltipY = 4;
      if (tooltipY + tooltipH > height - 4) tooltipY = height - tooltipH - 4;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(tooltipX, tooltipY, tooltipW, tooltipH),
        const Radius.circular(6),
      );

      canvas.drawRRect(
        rect,
        Paint()
          ..color = const Color(0xff1e293b).withValues(alpha: 0.9)
          ..style = PaintingStyle.fill,
      );

      textPainter.paint(canvas, Offset(tooltipX + 8, tooltipY + 6));
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final textSpan = TextSpan(text: text, style: style);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.hoverPosition != hoverPosition ||
        oldDelegate.maxVal != maxVal ||
        oldDelegate.barColor != barColor;
  }
}
