import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../controller/screenshot_edit_controller.dart';
import '../model/screenshot_edit.dart';
import '../model/screenshot_edit_geometry.dart';
import '../renderer/screenshot_edit_renderer.dart';

/// 放入 ScreenshotCanvas.imageOverlay 的标注层。
/// sessionId 隔离设备/编辑会话；source、mosaicImage 由外层工作区持有并释放。
class ScreenshotEditOverlay extends ConsumerStatefulWidget {
  const ScreenshotEditOverlay({
    super.key,
    required this.sessionId,
    required this.source,
    required this.mosaicImage,
    required this.rotation,
    required this.busy,
  });

  final String sessionId;
  final ui.Image source;
  final ui.Image? mosaicImage;
  final int rotation;
  final bool busy;

  @override
  ConsumerState<ScreenshotEditOverlay> createState() =>
      _ScreenshotEditOverlayState();
}

class _ScreenshotEditOverlayState extends ConsumerState<ScreenshotEditOverlay> {
  int? _pointer;

  Size get _imageSize =>
      Size(widget.source.width.toDouble(), widget.source.height.toDouble());

  Offset _imagePoint(Offset local) =>
      screenshotEditImagePoint(local, _imageSize, widget.rotation);

  Offset _clampedPoint(Offset local) {
    final point = _imagePoint(local);
    return Offset(
      point.dx.clamp(0, _imageSize.width),
      point.dy.clamp(0, _imageSize.height),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = screenshotEditControllerProvider(widget.sessionId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final drawing = state.tool != ScreenshotEditTool.pan && !widget.busy;
    return IgnorePointer(
      ignoring: !drawing,
      child: MouseRegion(
        cursor: SystemMouseCursors.precise,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_pointer != null || event.buttons != kPrimaryMouseButton) {
              return;
            }
            final point = _imagePoint(event.localPosition);
            if (!(Offset.zero & _imageSize).contains(point)) return;
            if (state.marks.length >= ScreenshotEditController.maxMarks) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n
                        .t('screenshotEditLimit')
                        .replaceAll(
                          '{count}',
                          '${ScreenshotEditController.maxMarks}',
                        ),
                  ),
                ),
              );
              return;
            }
            _pointer = event.pointer;
            controller.begin(point);
          },
          onPointerMove: (event) {
            if (_pointer == event.pointer) {
              controller.update(_clampedPoint(event.localPosition));
            }
          },
          onPointerUp: (event) {
            if (_pointer != event.pointer) return;
            controller.update(_clampedPoint(event.localPosition));
            controller.end();
            _pointer = null;
          },
          onPointerCancel: (event) {
            if (_pointer != event.pointer) return;
            controller.cancelStroke();
            _pointer = null;
          },
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _EditPainter(
                widget.source,
                widget.mosaicImage,
                widget.rotation,
                state.marks,
                state.draft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 只绘制透明标注层，预览和 PNG 导出复用同一个 Renderer。
class _EditPainter extends CustomPainter {
  _EditPainter(this.source, this.mosaic, this.rotation, this.marks, this.draft);

  final ui.Image source;
  final ui.Image? mosaic;
  final int rotation;
  final List<ScreenshotEditMark> marks;
  final ScreenshotEditMark? draft;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotation * math.pi / 180);
    canvas.translate(-source.width / 2, -source.height / 2);
    canvas.clipRect(
      Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    );
    ScreenshotEditRenderer.paint(canvas, source, [
      ...marks,
      ?draft,
    ], mosaicImage: mosaic);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EditPainter oldDelegate) =>
      source != oldDelegate.source ||
      mosaic != oldDelegate.mosaic ||
      rotation != oldDelegate.rotation ||
      marks != oldDelegate.marks ||
      draft != oldDelegate.draft;
}
