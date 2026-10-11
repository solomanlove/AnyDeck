import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
  int? _pointer;
  DateTime? _downAt;
  Size? _gesturePoints;
  Size? _gesturePixels;
  String? _gestureOrientation;
  Size? _reportedVideoSize;
  Size? _reportedViewport;

  void _cancel() {
    _down = null;
    _pointer = null;
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
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            _cancel();
            if (!control.ready ||
                control.busy ||
                event.buttons != kPrimaryMouseButton) {
              return;
            }
            _down = convert(event.localPosition);
            if (_down == null) return;
            _pointer = event.pointer;
            _downAt = DateTime.now();
            _gesturePoints = points;
            _gesturePixels = pixels;
            _gestureOrientation = control.orientation;
          },
          onPointerCancel: (_) => _cancel(),
          onPointerUp: (event) {
            final from = _down;
            final to = convert(event.localPosition);
            final duration = _downAt == null
                ? 400
                : DateTime.now().difference(_downAt!).inMilliseconds;
            final valid =
                _pointer == event.pointer &&
                _gesturePoints == points &&
                _gesturePixels == pixels &&
                _gestureOrientation == control.orientation;
            _cancel();
            if (!valid ||
                from == null ||
                to == null ||
                !control.ready ||
                control.busy) {
              return;
            }
            final notifier = ref.read(
              iosControlProvider(widget.deviceId).notifier,
            );
            if ((to - from).distance < 5) {
              notifier.perform('tap', {'x': to.dx, 'y': to.dy});
            } else {
              notifier.perform('swipe', {
                'fromX': from.dx,
                'fromY': from.dy,
                'toX': to.dx,
                'toY': to.dy,
                'durationMs': duration.clamp(100, 1500),
              });
            }
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
