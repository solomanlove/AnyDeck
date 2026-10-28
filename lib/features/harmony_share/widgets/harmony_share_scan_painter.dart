import 'package:flutter/material.dart';

/// 扫描装饰绘制；phase 驱动重绘而不重建设备卡片，静止时保留基础轨道。
class HarmonyShareScanPainter extends CustomPainter {
  HarmonyShareScanPainter({
    required this.color,
    required this.phase,
    required this.active,
  }) : super(repaint: phase);

  final Color color;
  final Animation<double> phase;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color.withValues(alpha: .1);
    for (final radius in [170.0, 260.0, 350.0]) {
      canvas.drawCircle(center, radius, paint);
    }
    if (!active) return;
    paint.strokeWidth = 1.5;
    for (final offset in [0.0, .5]) {
      final value = (phase.value + offset) % 1;
      paint.color = color.withValues(alpha: .18 * (1 - value));
      canvas.drawCircle(center, 155 + value * 240, paint);
    }
  }

  @override
  bool shouldRepaint(HarmonyShareScanPainter oldDelegate) =>
      color != oldDelegate.color ||
      active != oldDelegate.active ||
      phase != oldDelegate.phase;
}
