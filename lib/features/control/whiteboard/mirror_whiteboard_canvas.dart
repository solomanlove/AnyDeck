import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'mirror_whiteboard_controller.dart';

/// 覆盖在实际视频 Texture 上的透明画布；仅开启白板时拦截鼠标。
/// controller 由投屏窗口创建，窗口关闭时释放；画布只处理本地绘制。
/// 用法：在视频 Texture 的 Stack 顶层传入当前窗口的 controller。
class MirrorWhiteboardCanvas extends StatefulWidget {
  const MirrorWhiteboardCanvas({super.key, required this.controller});

  /// 当前投屏窗口的白板状态和笔迹来源。
  final MirrorWhiteboardController controller;

  @override
  State<MirrorWhiteboardCanvas> createState() => _MirrorWhiteboardCanvasState();
}

class _MirrorWhiteboardCanvasState extends State<MirrorWhiteboardCanvas> {
  double? _aspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isEmpty) return const SizedBox.shrink();
        final ratio = size.width / size.height;
        if (_aspectRatio != null && ((_aspectRatio! > 1) != (ratio > 1))) {
          // 横竖屏切换后旧轨迹已不对应新内容，清除本窗口标注。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.controller.clear();
          });
        }
        _aspectRatio = ratio;
        return AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => IgnorePointer(
            ignoring: !widget.controller.active,
            child: MouseRegion(
              cursor: widget.controller.active
                  ? SystemMouseCursors.precise
                  : MouseCursor.defer,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  if (event.buttons == kPrimaryMouseButton) {
                    widget.controller.begin(
                      event.pointer,
                      _point(event.localPosition, size),
                    );
                  }
                },
                onPointerMove: (event) => widget.controller.update(
                  event.pointer,
                  _point(event.localPosition, size),
                ),
                onPointerUp: (event) => widget.controller.end(event.pointer),
                onPointerCancel: (event) =>
                    widget.controller.cancel(event.pointer),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _WhiteboardPainter(widget.controller),
                    size: size,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Offset _point(Offset local, Size size) =>
      Offset(local.dx / size.width, local.dy / size.height);
}

class _WhiteboardPainter extends CustomPainter {
  _WhiteboardPainter(this.controller) : super(repaint: controller);

  final MirrorWhiteboardController controller;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in controller.strokes) {
      _draw(canvas, size, stroke.points, stroke.color);
    }
    if (controller.draft case final points?) {
      _draw(canvas, size, points, controller.draftColor);
    }
  }

  void _draw(Canvas canvas, Size size, List<Offset> points, Color color) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    Offset actual(Offset point) =>
        Offset(point.dx * size.width, point.dy * size.height);
    if (points.length == 1) {
      canvas.drawCircle(
        actual(points.first),
        2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()
      ..moveTo(actual(points.first).dx, actual(points.first).dy);
    for (final point in points.skip(1)) {
      final position = actual(point);
      path.lineTo(position.dx, position.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WhiteboardPainter oldDelegate) =>
      oldDelegate.controller != controller;
}
