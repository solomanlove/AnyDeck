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

  static Future<void> fitWindowToAspectRatio({
    required MethodChannel windowChannel,
    required double aspectRatio,
    required double viewerW,
    required double viewerH,
  }) async {
    if (!_isValid(aspectRatio) || !_isValid(viewerW) || !_isValid(viewerH)) {
      return;
    }

    final frame = await getWindowFrame(windowChannel);
    if (frame == null || !_isValid(frame.width) || !_isValid(frame.height)) {
      return;
    }

    final containerRatio = viewerW / viewerH;
    if (!_isValid(containerRatio)) return;

    var deltaW = 0.0;
    var deltaH = 0.0;
    if (containerRatio > aspectRatio) {
      deltaW = viewerH * aspectRatio - viewerW;
    } else if (containerRatio < aspectRatio) {
      deltaH = viewerW / aspectRatio - viewerH;
    }

    if (deltaW.abs() < 4 && deltaH.abs() < 4) return;
    final newWindowW = frame.width + deltaW;
    final newWindowH = frame.height + deltaH;
    if (newWindowW < 200 || newWindowH < 200) return;
    if (!_isValid(newWindowW) || !_isValid(newWindowH)) return;

    final newLeft = frame.left - deltaW / 2;
    final newTop = frame.top - deltaH / 2;
    if (!_isValid(newLeft) || !_isValid(newTop)) return;

    if (Platform.isMacOS) {
      try {
        final frameArgs = {
          'left': newLeft,
          'top': newTop,
          'width': newWindowW,
          'height': newWindowH,
        };
        await windowChannel.invokeMethod('setWindowFrame', frameArgs);
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
