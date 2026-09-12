import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/usage/companion_history.dart';

/// 离线轨迹示意图，无地图底图；points 按采集时间整理，最多绘制最近 1000 点。
/// 不跨越超过 30 分钟的缺口、时钟倒退或国际日期变更线连接轨迹。
class LocationTrailView extends StatelessWidget {
  const LocationTrailView({super.key, required this.points});
  final List<LocationRecord> points;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _TrailPainter(points, Theme.of(context).colorScheme),
  );
}

class _TrailPainter extends CustomPainter {
  _TrailPainter(this.points, this.colors);
  final List<LocationRecord> points;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = colors.surfaceContainerHighest,
    );
    if (points.isEmpty || size.width < 32 || size.height < 32) return;
    final ordered = points.take(1000).toList()
      ..sort((a, b) => a.capturedAtMs.compareTo(b.capturedAtMs));
    final meanLat =
        ordered.map((p) => p.latitude).reduce((a, b) => a + b) / ordered.length;
    final projected = ordered
        .map(
          (p) => Offset(
            p.longitude * math.cos(meanLat * math.pi / 180),
            -p.latitude,
          ),
        )
        .toList();
    final minX = projected.map((p) => p.dx).reduce(math.min);
    final maxX = projected.map((p) => p.dx).reduce(math.max);
    final minY = projected.map((p) => p.dy).reduce(math.min);
    final maxY = projected.map((p) => p.dy).reduce(math.max);
    final scale = math.min(
      (size.width - 32) / math.max(maxX - minX, 0.00001),
      (size.height - 32) / math.max(maxY - minY, 0.00001),
    );
    Offset display(Offset point) => Offset(
      size.width / 2 + (point.dx - (minX + maxX) / 2) * scale,
      size.height / 2 + (point.dy - (minY + maxY) / 2) * scale,
    );
    final pen = Paint()
      ..color = colors.primary
      ..strokeWidth = 2;
    for (var i = 0; i < ordered.length; i++) {
      final point = ordered[i];
      if (i > 0) {
        final previous = ordered[i - 1];
        final gap = point.capturedAtMs - previous.capturedAtMs;
        if (gap >= 0 &&
            gap <= 30 * 60000 &&
            (point.longitude - previous.longitude).abs() < 180 &&
            !point.mock &&
            !previous.mock) {
          canvas.drawLine(
            display(projected[i - 1]),
            display(projected[i]),
            pen,
          );
        }
      }
      canvas.drawCircle(
        display(projected[i]),
        i == ordered.length - 1 ? 5 : 2,
        Paint()..color = point.mock ? colors.error : colors.primary,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrailPainter old) =>
      old.points != points || old.colors != colors;
}
