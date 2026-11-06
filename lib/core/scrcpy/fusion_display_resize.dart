import 'dart:math';

import 'package:flutter/foundation.dart';

/// 融合副屏的物理尺寸与密度；保持约 1300dp 的逻辑高度，让 App 随窗口宽高比重排。
class FusionDisplayGeometry {
  const FusionDisplayGeometry(this.width, this.height, this.densityDpi);

  static const int maxSide = 1600;
  static const int logicalHeightDp = 1300;

  final int width;
  final int height;
  final int densityDpi;

  /// 按窗口内的实际视频区域计算副屏尺寸，最长边限制为 1600 像素。
  factory FusionDisplayGeometry.fromViewport(double width, double height) {
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      throw ArgumentError('Invalid fusion viewport');
    }
    final scale = maxSide / max(width, height);
    final pixelWidth = _even((width * scale).round());
    final pixelHeight = _even((height * scale).round());
    final dpi = (160 * pixelHeight / logicalHeightDp).round().clamp(72, 640);
    return FusionDisplayGeometry(pixelWidth, pixelHeight, dpi);
  }

  String get newDisplay => '${width}x$height/$densityDpi';

  /// scrcpy 4.0 control 协议：21 + 两个 big endian uint16 尺寸。
  Uint8List get resizeMessage => Uint8List.fromList([
    21,
    width >> 8,
    width & 0xff,
    height >> 8,
    height & 0xff,
  ]);

  static int _even(int value) => (value.clamp(320, maxSide) ~/ 2) * 2;
}

/// 合并重复尺寸请求；density 与宽高使用同一份目标几何数据。
class FusionDisplayResizer {
  FusionDisplayGeometry? _last;

  FusionDisplayGeometry? requestFor(double viewportWidth, double viewportHeight) {
    if (viewportWidth <= 0 || viewportHeight <= 0) return null;
    final geometry = FusionDisplayGeometry.fromViewport(
      viewportWidth,
      viewportHeight,
    );
    if (_last?.width == geometry.width &&
        _last?.height == geometry.height &&
        _last?.densityDpi == geometry.densityDpi) {
      return null;
    }
    _last = geometry;
    return geometry;
  }

  /// 发送失败时允许下一次窗口事件重发相同几何数据。
  void retryLast() => _last = null;
}

/// 串行发送副屏尺寸与 density，避免连续拖动时旧命令晚完成并覆盖最终 DPI。
class FusionDisplayUpdateQueue {
  FusionDisplayUpdateQueue({
    required this.sendResize,
    required this.setDensity,
  });

  final Future<bool> Function(FusionDisplayGeometry) sendResize;
  final Future<bool> Function(FusionDisplayGeometry) setDensity;
  Future<void> _tail = Future<void>.value();

  Future<bool> submit(FusionDisplayGeometry geometry) {
    final update = _tail.then((_) async {
      if (!await sendResize(geometry)) return false;
      return setDensity(geometry);
    });
    _tail = update.then<void>((_) {}, onError: (_) {});
    return update;
  }
}
