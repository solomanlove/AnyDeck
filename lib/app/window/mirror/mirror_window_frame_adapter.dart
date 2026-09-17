import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// 处理独立投屏窗口的原生 frame 读取和宽高比适配。
class MirrorWindowFrameAdapter {
  const MirrorWindowFrameAdapter._();

  static Future<Rect?> getWindowFrame(MethodChannel windowChannel) async {
    if (Platform.isMacOS) {
      try {
        final res = await windowChannel.invokeMethod('getWindowFrame');
        if (res is Map) {
          final left = (res['left'] as num).toDouble();
          final top = (res['top'] as num).toDouble();
          final width = (res['width'] as num).toDouble();
          final height = (res['height'] as num).toDouble();
          return Rect.fromLTWH(left, top, width, height);
        }
      } on MissingPluginException {
        return _getWindowManagerBounds();
      } catch (e) {
        debugPrint('Failed to get window frame on macOS: $e');
      }
      return null;
    }
    return _getWindowManagerBounds();
  }

  /// 计算贴合指定比例后的新窗口 Frame。
  /// 当横竖屏方向发生翻转时，以原窗口中心点为锚点旋转并重设宽高。
  static Rect? calculateFittedFrame({
    required Rect frame,
    required double aspectRatio,
    required double viewerW,
    required double viewerH,
  }) {
    if (!_isValid(aspectRatio) || !_isValid(viewerW) || !_isValid(viewerH)) {
      return null;
    }
    if (!_isValid(frame.width) || !_isValid(frame.height)) {
      return null;
    }

    final containerRatio = viewerW / viewerH;
    if (!_isValid(containerRatio)) return null;

    final centerX = frame.left + frame.width / 2;
    final centerY = frame.top + frame.height / 2;

    final isOldPortrait = containerRatio < 1.0;
    final isNewLandscape = aspectRatio > 1.0;
    final isOldLandscape = containerRatio > 1.0;
    final isNewPortrait = aspectRatio < 1.0;
    final isOrientationSwapped =
        (isOldPortrait && isNewLandscape) || (isOldLandscape && isNewPortrait);

    final double newWindowW;
    final double newWindowH;
    double newLeft;
    double newTop;

    if (isOrientationSwapped) {
      var chromeHeight = frame.height - viewerH;
      if (chromeHeight < 30 || chromeHeight > 120) {
        chromeHeight = 58.0;
      }

      if (isOldPortrait && isNewLandscape) {
        // 竖屏转横屏：横屏内容基准宽度取原竖屏内容高度 viewerH
        final targetViewerW = viewerH;
        final targetViewerH = targetViewerW / aspectRatio;
        newWindowW = targetViewerW;
        newWindowH = targetViewerH + chromeHeight;
      } else {
        // 横屏转竖屏：竖屏内容基准高度取原横屏内容宽度 viewerW
        final targetViewerH = viewerW;
        final targetViewerW = targetViewerH * aspectRatio;
        newWindowW = targetViewerW;
        newWindowH = targetViewerH + chromeHeight;
      }

      // 以原窗口中心点为原点旋转定位
      newLeft = centerX - newWindowW / 2;
      newTop = centerY - newWindowH / 2;
    } else {
      // 同方向常规比例微调
      var deltaW = 0.0;
      var deltaH = 0.0;
      if (containerRatio > aspectRatio) {
        deltaW = viewerH * aspectRatio - viewerW;
      } else if (containerRatio < aspectRatio) {
        deltaH = viewerW / aspectRatio - viewerH;
      }

      if (deltaW.abs() < 4 && deltaH.abs() < 4) return null;
      newWindowW = frame.width + deltaW;
      newWindowH = frame.height + deltaH;
      newLeft = frame.left - deltaW / 2;
      newTop = frame.top - deltaH / 2;
    }

    if (newWindowW < 200 || newWindowH < 200) return null;
    if (!_isValid(newWindowW) || !_isValid(newWindowH)) return null;
    if (!_isValid(newLeft) || !_isValid(newTop)) return null;

    if (newLeft < 0) newLeft = 0;
    if (newTop < 0) newTop = 0;

    return Rect.fromLTWH(newLeft, newTop, newWindowW, newWindowH);
  }

  /// 方向翻转时先以内容长边为边长扩展为正方形，窗口中心保持不变。
  static Rect? calculateSquareTransitionFrame({
    required Rect frame,
    required double targetAspectRatio,
    required double viewerW,
    required double viewerH,
  }) {
    if ((viewerW < viewerH) == (targetAspectRatio < 1)) {
      return null;
    }
    final chromeHeight = frame.height - viewerH;
    final side = viewerW > viewerH ? viewerW : viewerH;
    if (!_isValid(side) || !_isValid(chromeHeight)) return null;
    final width = side;
    final height = side + chromeHeight;
    return Rect.fromCenter(
      center: frame.center,
      width: width,
      height: height,
    );
  }

  static Future<void> fitWindowToAspectRatio({
    required MethodChannel windowChannel,
    required double aspectRatio,
    required double viewerW,
    required double viewerH,
    bool animateRotation = false,
  }) async {
    final frame = await getWindowFrame(windowChannel);
    if (frame == null) return;

    final newFrame = calculateFittedFrame(
      frame: frame,
      aspectRatio: aspectRatio,
      viewerW: viewerW,
      viewerH: viewerH,
    );
    if (newFrame == null) return;

    if (animateRotation && Platform.isMacOS) {
      final square = calculateSquareTransitionFrame(
        frame: frame,
        targetAspectRatio: aspectRatio,
        viewerW: viewerW,
        viewerH: viewerH,
      );
      if (square != null) {
        try {
          await windowChannel.invokeMethod('animateWindowFrameSequence', {
            'middle': _frameArgs(square),
            'final': _frameArgs(newFrame),
          });
          return;
        } on MissingPluginException {
          // 旧版窗口桥接不支持动画时，继续使用直接贴合。
        } catch (e) {
          debugPrint('Failed to animate window frame on macOS: $e');
        }
      }
    }

    final newLeft = newFrame.left;
    final newTop = newFrame.top;
    final newWindowW = newFrame.width;
    final newWindowH = newFrame.height;

    if (Platform.isMacOS) {
      try {
        await windowChannel.invokeMethod('setWindowFrame', _frameArgs(newFrame));
        return;
      } on MissingPluginException {
        // 脚本直启投屏窗口时没有 desktop_multi_window 子窗口原生 channel。
      } catch (e) {
        debugPrint('Failed to set window frame on macOS: $e');
        return;
      }
      await _setWindowManagerBounds(
        Rect.fromLTWH(newLeft, newTop, newWindowW, newWindowH),
      );
    } else {
      await _setWindowManagerBounds(
        Rect.fromLTWH(newLeft, newTop, newWindowW, newWindowH),
      );
    }
  }

  static bool _isValid(double value) {
    return value > 0 && !value.isNaN && !value.isInfinite;
  }

  static Map<String, double> _frameArgs(Rect frame) => {
    'left': frame.left,
    'top': frame.top,
    'width': frame.width,
    'height': frame.height,
  };

  static Future<Rect?> _getWindowManagerBounds() async {
    try {
      return await windowManager.getBounds();
    } catch (e) {
      debugPrint('Failed to get window bounds via windowManager: $e');
      return null;
    }
  }

  static Future<void> _setWindowManagerBounds(Rect bounds) async {
    try {
      await windowManager.setBounds(bounds);
    } catch (e) {
      debugPrint('Failed to set window frame: $e');
    }
  }
}
