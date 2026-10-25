import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/l10n/app_localizations.dart';

/// 遥控器方向盘；[onKey] 接收 Android 方向键码，由调用方路由到 ADB 或 HDC。
class RemoteDirectionPad extends StatefulWidget {
  const RemoteDirectionPad({super.key, required this.onKey});

  final Future<void> Function(int keyCode) onKey;

  @override
  State<RemoteDirectionPad> createState() => _RemoteDirectionPadState();
}

class _RemoteDirectionPadState extends State<RemoteDirectionPad> {
  int? _hoverKey;
  int? _pressedKey;
  bool _busy = false;

  // 圆心的 OK 与四个扇区使用同一套坐标判断，避免显示区域和可点击区域错位。
  int? _keyAt(Offset point) {
    final offset = point - const Offset(95, 95);
    final distance = offset.distance;
    if (distance > 95) return null;
    if (distance <= 42) return 23;
    if (offset.dy.abs() >= offset.dx.abs()) {
      return offset.dy < 0 ? 19 : 20;
    }
    return offset.dx < 0 ? 21 : 22;
  }

  Future<void> _sendKey(int keyCode) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onKey(keyCode);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeKey = _pressedKey ?? _hoverKey;
    final tooltip = switch (activeKey) {
      19 => context.l10n.t('remoteUp'),
      20 => context.l10n.t('remoteDown'),
      21 => context.l10n.t('remoteLeft'),
      22 => context.l10n.t('remoteRight'),
      23 => 'OK',
      _ => context.l10n.t('remoteController'),
    };

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        onHover: (event) {
          final key = _keyAt(event.localPosition);
          if (_hoverKey != key) setState(() => _hoverKey = key);
        },
        onExit: (_) => setState(() => _hoverKey = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              setState(() => _pressedKey = _keyAt(details.localPosition)),
          onTapCancel: () => setState(() => _pressedKey = null),
          onTapUp: (details) {
            final key = _keyAt(details.localPosition);
            final pressedKey = _pressedKey;
            setState(() => _pressedKey = null);
            if (key != null && key == pressedKey) _sendKey(key);
          },
          child: SizedBox(
            width: 190,
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size.square(190),
                  painter: _DirectionPadPainter(
                    baseColor: scheme.surfaceContainerHighest,
                    activeColor: Color.alphaBlend(
                      scheme.onSurface.withValues(alpha: 0.13),
                      scheme.surfaceContainerHighest,
                    ),
                    centerColor: scheme.surface,
                    dotColor: scheme.onSurface,
                    separatorColor: scheme.outlineVariant.withValues(
                      alpha: 0.45,
                    ),
                    activeKey: activeKey,
                  ),
                ),
                IgnorePointer(
                  child: Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 绘制与点击分区一致的四个 90° 扇区及中心确认键。
class _DirectionPadPainter extends CustomPainter {
  const _DirectionPadPainter({
    required this.baseColor,
    required this.activeColor,
    required this.centerColor,
    required this.dotColor,
    required this.separatorColor,
    required this.activeKey,
  });

  final Color baseColor;
  final Color activeColor;
  final Color centerColor;
  final Color dotColor;
  final Color separatorColor;
  final int? activeKey;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final circle = Rect.fromCircle(center: center, radius: 95);
    const sectors = <(int, double)>[
      (19, -3 * math.pi / 4),
      (22, -math.pi / 4),
      (20, math.pi / 4),
      (21, 3 * math.pi / 4),
    ];
    for (final (key, angle) in sectors) {
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(circle, angle, math.pi / 2, false)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = key == activeKey ? activeColor : baseColor,
      );
      final dotAngle = angle + math.pi / 4;
      canvas.drawCircle(
        center + Offset(math.cos(dotAngle) * 67, math.sin(dotAngle) * 67),
        3,
        Paint()..color = dotColor,
      );
    }
    for (final angle in [
      -3 * math.pi / 4,
      -math.pi / 4,
      math.pi / 4,
      3 * math.pi / 4,
    ]) {
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * 42,
        center + direction * 95,
        Paint()
          ..color = separatorColor
          ..strokeWidth = 1,
      );
    }
    canvas.drawCircle(
      center,
      42,
      Paint()..color = activeKey == 23 ? activeColor : centerColor,
    );
  }

  @override
  bool shouldRepaint(covariant _DirectionPadPainter oldDelegate) =>
      oldDelegate.activeKey != activeKey ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.centerColor != centerColor ||
      oldDelegate.dotColor != dotColor ||
      oldDelegate.separatorColor != separatorColor;
}
