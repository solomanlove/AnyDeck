import 'dart:ui';

/// 只接受真实画面范围内的位置；将 contain 黑边与像素比例统一换算成 iOS point。
class IosMirrorCoordinates {
  static Offset? toPoints(
    Offset position,
    Size viewport,
    Size pixels,
    Size points,
  ) {
    if ([
      viewport.width,
      viewport.height,
      pixels.width,
      pixels.height,
      points.width,
      points.height,
    ].any((v) => !v.isFinite || v <= 0)) {
      return null;
    }
    // 旋转时视频与 WDA 可能短暂不同步，宁可暂停输入也不误点旧方向。
    if ((pixels.width > pixels.height) != (points.width > points.height)) {
      return null;
    }
    final scale = (viewport.width / pixels.width).clamp(
      0,
      viewport.height / pixels.height,
    );
    final width = pixels.width * scale;
    final height = pixels.height * scale;
    final left = (viewport.width - width) / 2;
    final top = (viewport.height - height) / 2;
    if (position.dx < left ||
        position.dy < top ||
        position.dx >= left + width ||
        position.dy >= top + height) {
      return null;
    }
    return Offset(
      (position.dx - left) / width * points.width,
      (position.dy - top) / height * points.height,
    );
  }
}
