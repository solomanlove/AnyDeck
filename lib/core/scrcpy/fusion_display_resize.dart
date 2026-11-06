import 'dart:math';

import 'package:flutter/foundation.dart';

/// scrcpy 4.0 control 协议：21 + 两个 big endian uint16 尺寸。
class FusionDisplayResizer {
  FusionDisplayResizer(String initialDisplay) {
    final match = RegExp(r'^(\d+)x(\d+)').firstMatch(initialDisplay);
    initialWidth = int.tryParse(match?.group(1) ?? '') ?? 1080;
    initialHeight = int.tryParse(match?.group(2) ?? '') ?? 1920;
  }

  late final int initialWidth;
  late final int initialHeight;
  double? _scale;
  int? _lastWidth;
  int? _lastHeight;

  /// 首次按真实 viewport 建立 DPI 比例，后续拖动只改变虚拟屏宽高。
  Uint8List? messageFor(double viewportWidth, double viewportHeight) {
    if (viewportWidth <= 0 || viewportHeight <= 0) return null;
    _scale ??= min(
      initialWidth / viewportWidth,
      initialHeight / viewportHeight,
    );
    final width = _even((viewportWidth * _scale!).round());
    final height = _even((viewportHeight * _scale!).round());
    if (width == _lastWidth && height == _lastHeight) return null;
    _lastWidth = width;
    _lastHeight = height;
    return Uint8List.fromList([
      21,
      width >> 8,
      width & 0xff,
      height >> 8,
      height & 0xff,
    ]);
  }

  /// 发送失败时允许下次窗口事件重发相同尺寸。
  void retryLast() {
    _lastWidth = null;
    _lastHeight = null;
  }

  int _even(int value) => (value.clamp(320, 4096) ~/ 2) * 2;
}
