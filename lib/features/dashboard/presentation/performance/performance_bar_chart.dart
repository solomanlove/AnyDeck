import 'package:flutter/material.dart';
import 'performance_charts.dart';

/// 支持渐变柱子和悬停 Tooltip 交互的柱状图 (专门针对 FPS)
class InteractiveBarChart extends StatefulWidget {
  const InteractiveBarChart({
    super.key,
    required this.data,
    required this.maxVal,
    required this.barColor,
    this.unit = '',
    this.windowSize = 90,
  });

  final List<ChartDataPoint> data;
  final double maxVal;
  final Color barColor;
  final String unit;
  final int windowSize;

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
          windowSize: widget.windowSize,
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
    required this.windowSize,
  });

  final List<ChartDataPoint> data;
  final double maxVal;
  final Color barColor;
  final Offset? hoverPosition;
  final String unit;
  final int windowSize;

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

    // 纵向时间网格 (根据时间戳每隔 10 秒绘制一条垂直网格线并附带时间戳标签)
    final latestTime = data.last.timestamp ?? DateTime.now();
    final startTime = latestTime.subtract(Duration(seconds: windowSize));
    
    final int startUnix = startTime.millisecondsSinceEpoch ~/ 1000;
    final int firstBoundaryUnix = ((startUnix ~/ 10) + 1) * 10;
    DateTime boundary = DateTime.fromMillisecondsSinceEpoch(firstBoundaryUnix * 1000);

    while (boundary.isBefore(latestTime) || boundary.isAtSameMomentAs(latestTime)) {
      final double offsetSeconds = latestTime.difference(boundary).inMilliseconds / 1000.0;
      final double x = width - (offsetSeconds / windowSize) * width;
      
      if (x >= 0 && x <= width) {
        canvas.drawLine(Offset(x, 0), Offset(x, height), gridPaint);
        
        final timeStr = '${boundary.hour.toString().padLeft(2, '0')}:'
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
        
        textPainter.paint(canvas, Offset(textX, 4));
      }
      
      boundary = boundary.add(const Duration(seconds: 10));
    }

    // 绘制网格文字
    const textStyle = TextStyle(color: Color(0xff80868b), fontSize: 10, fontWeight: FontWeight.w500);
    _drawText(canvas, '${maxVal.toInt()}$unit', Offset(6, 4), textStyle);
    _drawText(canvas, '${(maxVal / 2).toInt()}$unit', Offset(6, height / 2 - 6), textStyle);

    // 计算柱状图宽度
    final double slotW = width / windowSize;
    final double barW = slotW * 0.8;
    final double spaceW = slotW * 0.2;

    int? hoveredIndex;
    if (hoverPosition != null) {
      double minDistance = double.infinity;
      for (int i = 0; i < data.length; i++) {
        final point = data[i];
        final pointTime = point.timestamp ?? latestTime.subtract(Duration(seconds: data.length - 1 - i));
        final double offsetSeconds = latestTime.difference(pointTime).inMilliseconds / 1000.0;
        final double barCenterX = width - (offsetSeconds + 0.5) * slotW;
        final double distance = (hoverPosition!.dx - barCenterX).abs();
        if (distance < minDistance && distance < slotW * 1.5) {
          minDistance = distance;
          hoveredIndex = i;
        }
      }
    }

    for (int i = 0; i < data.length; i++) {
      final point = data[i];
      final pointTime = point.timestamp ?? latestTime.subtract(Duration(seconds: data.length - 1 - i));
      final double offsetSeconds = latestTime.difference(pointTime).inMilliseconds / 1000.0;
      
      final double x = width - (offsetSeconds + 1) * slotW + spaceW / 2;
      final double y = height - (point.value / maxVal * height);

      if (x >= -barW && x <= width) {
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
    }

    // 绘制悬停 Tooltip
    if (hoveredIndex != null) {
      final targetData = data[hoveredIndex];
      final pointTime = targetData.timestamp ?? latestTime.subtract(Duration(seconds: data.length - 1 - hoveredIndex));
      final double offsetSeconds = latestTime.difference(pointTime).inMilliseconds / 1000.0;
      final double x = width - (offsetSeconds + 0.5) * slotW;
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
        oldDelegate.barColor != barColor ||
        oldDelegate.windowSize != windowSize;
  }
}
