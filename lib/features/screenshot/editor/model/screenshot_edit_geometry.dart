import 'dart:math' as math;
import 'dart:ui';

/// 将 Viewer 子节点（已去除缩放和平移）的坐标还原为原图像素坐标。
/// 绘制和命中使用相同的旋转中心，导出不依赖窗口大小或屏幕 DPR。
Offset screenshotEditImagePoint(
  Offset scenePoint,
  Size imageSize,
  int rotation,
) {
  final sideways = rotation == 90 || rotation == 270;
  final rotatedSize = sideways
      ? Size(imageSize.height, imageSize.width)
      : imageSize;
  final centered = scenePoint - rotatedSize.center(Offset.zero);
  final radians = -rotation * math.pi / 180;
  return Offset(
        centered.dx * math.cos(radians) - centered.dy * math.sin(radians),
        centered.dx * math.sin(radians) + centered.dy * math.cos(radians),
      ) +
      imageSize.center(Offset.zero);
}
