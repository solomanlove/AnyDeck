import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'embedded_scrcpy_geometry.dart';

/// 按当前横竖屏比例渲染 scrcpy Texture，并只在真实画面区域接收事件。
class EmbeddedScrcpyTextureSurface extends StatelessWidget {
  const EmbeddedScrcpyTextureSurface({
    super.key,
    required this.textureKey,
    required this.textureId,
    required this.aspectRatio,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onPointerCancel,
    required this.onPointerPanZoomStart,
    required this.onPointerPanZoomUpdate,
    required this.onPointerSignal,
    this.overlay,
  });

  final GlobalKey textureKey;
  final int textureId;
  final double aspectRatio;
  final PointerDownEventListener onPointerDown;
  final PointerMoveEventListener onPointerMove;
  final PointerUpEventListener onPointerUp;
  final PointerCancelEventListener onPointerCancel;
  final ValueChanged<PointerPanZoomStartEvent> onPointerPanZoomStart;
  final ValueChanged<PointerPanZoomUpdateEvent> onPointerPanZoomUpdate;
  final ValueChanged<PointerSignalEvent> onPointerSignal;

  /// 可选的画面叠加层（如轨迹可视化 Overlay），自动对齐真实视频纹理尺寸
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textureSize = ScrcpyVideoGeometry.fitTextureSize(
            constraints.biggest,
            aspectRatio,
          );
          if (textureSize == Size.zero) {
            return const SizedBox.shrink();
          }

          return Center(
            child: SizedBox(
              width: textureSize.width,
              height: textureSize.height,
              child: Listener(
                key: textureKey,
                behavior: HitTestBehavior.opaque,
                onPointerDown: onPointerDown,
                onPointerMove: onPointerMove,
                onPointerUp: onPointerUp,
                onPointerCancel: onPointerCancel,
                onPointerPanZoomStart: onPointerPanZoomStart,
                onPointerPanZoomUpdate: onPointerPanZoomUpdate,
                onPointerSignal: onPointerSignal,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Texture(textureId: textureId),
                    ?overlay,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
