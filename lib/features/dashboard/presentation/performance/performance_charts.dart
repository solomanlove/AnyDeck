import 'package:flutter/material.dart';

/// 统一图表采样数据点模型。
class ChartDataPoint {
  const ChartDataPoint({
    required this.value,
    required this.label,
    this.timestamp,
  });

  final double value; // 具体数值
  final String label; // 时间戳字符串 (如 "15:52:30")
  final DateTime? timestamp; // 真实时间戳
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
    this.windowSize = 90,
  });

  final List<ChartDataPoint> data;
  final double maxVal;
  final Color lineColor;
  final List<Color> fillGradientColors;
  final String unit;
  final int windowSize;

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
          windowSize: widget.windowSize,
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
    required this.windowSize,
  });

  final List<ChartDataPoint> data;
  final double maxVal;
  final Color lineColor;
  final List<Color> gradientColors;
  final Offset? hoverPosition;
  final String unit;
  final int windowSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double width = size.width;
    final double height = size.height;
    final double chartHeight = height - 18; // 预留底部 18px 绘制时间轴标签

    // 绘制背景网格
    final gridPaint = Paint()
      ..color = const Color(0xffeceef1)
      ..strokeWidth = 1.0;

    // 水平分割线
    canvas.drawLine(const Offset(0, 2), Offset(width, 2), gridPaint); // 100%
    canvas.drawLine(
      Offset(0, chartHeight / 2),
      Offset(width, chartHeight / 2),
      gridPaint,
    ); // 50%
    canvas.drawLine(Offset(0, chartHeight), Offset(width, chartHeight), gridPaint); // 0%

    // 纵向时间网格 (根据时间戳每隔 10 秒绘制一条垂直网格线并附带时间戳标签)
    final latestTime = data.last.timestamp ?? DateTime.now();
    final startTime = latestTime.subtract(Duration(seconds: windowSize));

    final int startUnix = startTime.millisecondsSinceEpoch ~/ 1000;
    final int firstBoundaryUnix = ((startUnix ~/ 10) + 1) * 10;
    DateTime boundary = DateTime.fromMillisecondsSinceEpoch(
      firstBoundaryUnix * 1000,
    );

    while (boundary.isBefore(latestTime) ||
        boundary.isAtSameMomentAs(latestTime)) {
      final double offsetSeconds =
          latestTime.difference(boundary).inMilliseconds / 1000.0;
      final double x = width - (offsetSeconds / windowSize) * width;

      if (x >= 0 && x <= width) {
        canvas.drawLine(Offset(x, 0), Offset(x, chartHeight), gridPaint);

        final timeStr =
            '${boundary.hour.toString().padLeft(2, '0')}:'
            '${boundary.minute.toString().padLeft(2, '0')}:'
            '${boundary.second.toString().padLeft(2, '0')}';

        final textSpan = TextSpan(
          text: timeStr,
          style: const TextStyle(
            color: Color(0xff80868b),
            fontSize: 9,
            fontWeight: FontWeight.w400,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout();

        double textX = x - textPainter.width / 2;
        textX = textX.clamp(4.0, width - textPainter.width - 4.0);

        textPainter.paint(canvas, Offset(textX, chartHeight + 4));
      }

      boundary = boundary.add(const Duration(seconds: 10));
    }

    // 绘制坐标轴文字
    const textStyle = TextStyle(
      color: Color(0xff80868b),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );
    _drawText(canvas, '${maxVal.toInt()}$unit', const Offset(6, 4), textStyle);
    _drawText(
      canvas,
      '${(maxVal / 2).toInt()}$unit',
      Offset(6, chartHeight / 2 - 6),
      textStyle,
    );
    _drawText(
      canvas,
      '0$unit',
      Offset(6, chartHeight - 12),
      textStyle,
    );

    // 计算折线点坐标
    final List<Offset> points = [];
    for (int i = 0; i < data.length; i++) {
      final point = data[i];
      final pointTime =
          point.timestamp ??
          latestTime.subtract(Duration(seconds: data.length - 1 - i));
      final double offsetSeconds =
          latestTime.difference(pointTime).inMilliseconds / 1000.0;
      final double x = width - (offsetSeconds / windowSize) * width;
      final double y = chartHeight - (point.value / maxVal * chartHeight);
      points.add(Offset(x.clamp(0.0, width), y.clamp(2.0, chartHeight)));
    }

    // 绘制面积渐变填充
    if (points.length > 1) {
      final fillPath = Path()
        ..moveTo(points.first.dx, chartHeight)
        ..lineTo(points.first.dx, points.first.dy);

      for (int i = 1; i < points.length; i++) {
        fillPath.lineTo(points[i].dx, points[i].dy);
      }
      fillPath.lineTo(points.last.dx, chartHeight);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
        ).createShader(Rect.fromLTRB(0, 0, width, chartHeight));

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
    if (hoverPosition != null && data.isNotEmpty) {
      final double hoverX = hoverPosition!.dx;
      int closestIndex = 0;
      double minDistance = double.infinity;
      for (int i = 0; i < points.length; i++) {
        final double distance = (hoverX - points[i].dx).abs();
        if (distance < minDistance) {
          minDistance = distance;
          closestIndex = i;
        }
      }

      final targetPoint = points[closestIndex];
      final targetData = data[closestIndex];

      // 1. 绘制纵向指示虚线
      final dashPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.6)
        ..strokeWidth = 1.0;

      double startY = 0;
      const dashWidth = 4.0;
      const dashSpace = 4.0;
      while (startY < chartHeight) {
        canvas.drawLine(
          Offset(targetPoint.dx, startY),
          Offset(targetPoint.dx, startY + dashWidth),
          dashPaint,
        );
        startY += dashWidth + dashSpace;
      }

      // 2. 绘制选中数据点发光圆圈
      canvas.drawCircle(
        targetPoint,
        6.0,
        Paint()..color = lineColor.withValues(alpha: 0.3),
      );
      canvas.drawCircle(targetPoint, 4.0, Paint()..color = lineColor);
      canvas.drawCircle(targetPoint, 2.0, Paint()..color = Colors.white);

      // 3. 绘制 Tooltip 箱子
      final tooltipText =
          '${targetData.value.toStringAsFixed(1)}$unit\n${targetData.label}';
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
      if (tooltipY + tooltipH > chartHeight - 4) tooltipY = chartHeight - tooltipH - 4;

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
        oldDelegate.lineColor != lineColor ||
        oldDelegate.windowSize != windowSize;
  }
}
