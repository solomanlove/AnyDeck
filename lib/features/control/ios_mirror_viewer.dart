import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ios/ios_control_provider.dart';
import '../../core/ios/ios_mirror_coordinates.dart';
import '../../core/ios/ios_mirror_service.dart';

/// macOS iPhone USB Texture 视图；port 为兼容旧调用保留，实际传入 Texture ID。
/// 所有点击只落入视频区域；WDA 手势在抬起时一次提交，避免逐像素请求。
class IosMirrorViewer extends ConsumerStatefulWidget {
  const IosMirrorViewer({
    super.key,
    required this.deviceId,
    required this.port,
    this.onVideoGeometryChanged,
  });
  final String deviceId;
  final int port;
  final void Function(int width, int height, Size viewport)?
  onVideoGeometryChanged;
  @override
  ConsumerState<IosMirrorViewer> createState() => _IosMirrorViewerState();
}

class _IosMirrorViewerState extends ConsumerState<IosMirrorViewer> {
  Offset? _down;
  Offset? _lastDrag;
  DateTime? _downAt;
  Size? _gesturePoints;
  Size? _gesturePixels;
  String? _gestureOrientation;
  Size? _reportedVideoSize;
  Size? _reportedViewport;

  void _cancel() {
    _down = null;
    _lastDrag = null;
    _downAt = null;
  }

  @override
  void didUpdateWidget(covariant IosMirrorViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId ||
        oldWidget.port != widget.port) {
      _cancel();
      _reportedVideoSize = null;
      _reportedViewport = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final control = ref.watch(iosControlProvider(widget.deviceId));
    final data = ref.watch(iosUsbFrameProvider(widget.deviceId));
    final pixels = Size(
      (data['width'] as num?)?.toDouble() ?? 0,
      (data['height'] as num?)?.toDouble() ?? 0,
    );
    final points = Size(control.width, control.height);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        if (!pixels.isEmpty &&
            (pixels != _reportedVideoSize || viewport != _reportedViewport)) {
          _reportedVideoSize = pixels;
          _reportedViewport = viewport;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                _reportedVideoSize != pixels ||
                _reportedViewport != viewport) {
              return;
            }
            widget.onVideoGeometryChanged?.call(
              pixels.width.toInt(),
              pixels.height.toInt(),
              viewport,
            );
          });
        }
        Offset? convert(Offset position) =>
            IosMirrorCoordinates.toPoints(position, viewport, pixels, points);
        bool canControl() {
          final current = ref.read(iosControlProvider(widget.deviceId));
          return current.ready && !current.busy;
        }

        void performTap(Offset position) {
          if (!canControl()) return;
          final target = convert(position);
          if (target == null) return;
          ref.read(iosControlProvider(widget.deviceId).notifier).perform(
            'tap',
            {'x': target.dx, 'y': target.dy},
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => performTap(details.localPosition),
          onPanStart: (details) {
            _cancel();
            if (!canControl()) return;
            _down = convert(details.localPosition);
            if (_down == null) return;
            _lastDrag = _down;
            _downAt = DateTime.now();
            _gesturePoints = points;
            _gesturePixels = pixels;
            _gestureOrientation = control.orientation;
          },
          onPanUpdate: (details) {
            if (_down == null) return;
            _lastDrag = convert(details.localPosition);
          },
          onPanCancel: _cancel,
          onPanEnd: (_) {
            final from = _down;
            final to = _lastDrag;
            final duration = _downAt == null
                ? 400
                : DateTime.now().difference(_downAt!).inMilliseconds;
            final current = ref.read(iosControlProvider(widget.deviceId));
            final valid =
                _gesturePoints == points &&
                _gesturePixels == pixels &&
                _gestureOrientation == current.orientation;
            _cancel();
            if (!valid ||
                from == null ||
                to == null ||
                !current.ready ||
                current.busy) {
              return;
            }
            final notifier = ref.read(
              iosControlProvider(widget.deviceId).notifier,
            );
            notifier.perform('swipe', {
              'fromX': from.dx,
              'fromY': from.dy,
              'toX': to.dx,
              'toY': to.dy,
              'durationMs': duration.clamp(100, 1500),
            });
          },
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: pixels.isEmpty
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: viewport.width,
                      height: viewport.height,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: pixels.width,
                          height: pixels.height,
                          child: Texture(textureId: widget.port),
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
