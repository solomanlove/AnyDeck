import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrcpy_flutter/scrcpy_flutter.dart';

import '../../../core/device_info/device_display_frame.dart';
import '../../../core/providers/app_providers.dart';

class MirrorAspectResult {
  const MirrorAspectResult({
    required this.aspectRatio,
    required this.shouldRestartStream,
  });

  final double aspectRatio;
  final bool shouldRestartStream;
}

/// 统一解析投屏窗口当前应该使用的横竖屏比例。
class MirrorAspectResolver {
  DeviceDisplayFrame? _displayFrame;
  bool _rotationChanged = false;
  bool _streamOrientationMismatch = false;

  int? _lastVideoWidth;
  int? _lastVideoHeight;

  void resetAfterStreamRestart() {
    _rotationChanged = false;
    _streamOrientationMismatch = false;
    _lastVideoWidth = null;
    _lastVideoHeight = null;
  }

  Future<double> resolveNow({
    required WidgetRef ref,
    required String deviceId,
    required String? resolution,
    required double Function(String?) fallbackAspect,
  }) async {
    await _refreshDisplayFrame(ref, deviceId);
    return await _resolveVideoAspect(deviceId) ??
        _displayFrame?.aspectRatio ??
        fallbackAspect(resolution);
  }

  Future<MirrorAspectResult> resolveForAutoFit({
    required WidgetRef ref,
    required String deviceId,
    required String? resolution,
    required double Function(String?) fallbackAspect,
  }) async {
    double? videoAspect;
    bool sizeChanged = false;
    try {
      final size = await ScrcpyFlutter.getVideoSize(deviceId: deviceId);
      if (size != null && size['width']! > 0 && size['height']! > 0) {
        final w = size['width']!;
        final h = size['height']!;
        // 视频分辨率发生变化说明设备可能旋转，立即强制刷新 displayFrame
        if (_lastVideoWidth != w || _lastVideoHeight != h) {
          _lastVideoWidth = w;
          _lastVideoHeight = h;
          sizeChanged = true;
        }
        videoAspect = w / h;
      }
    } catch (_) {}

    // 仅在 displayFrame 为空，或视频流实际分辨率改变时才拉取 dumpsys display
    if (_displayFrame == null || sizeChanged) {
      await _refreshDisplayFrame(ref, deviceId);
    }

    final displayFrame = _displayFrame;
    var hasOrientationMismatch = false;
    if (videoAspect != null && displayFrame != null) {
      if (displayFrame.isOrientationMismatch(videoAspect)) {
        _streamOrientationMismatch = true;
        hasOrientationMismatch = true;
      }
    }

    final aspectRatio = (videoAspect != null && displayFrame != null)
        ? displayFrame.chooseAspectRatio(videoAspect)
        : (videoAspect ??
              displayFrame?.aspectRatio ??
              fallbackAspect(resolution));

    final result = MirrorAspectResult(
      aspectRatio: aspectRatio,
      shouldRestartStream:
          _streamOrientationMismatch ||
          (_rotationChanged && hasOrientationMismatch),
    );
    _rotationChanged = false;
    _streamOrientationMismatch = false;
    return result;
  }

  Future<void> _refreshDisplayFrame(WidgetRef ref, String deviceId) async {
    try {
      final displayFrame = await DeviceDisplayFrame.read(
        ref.read(adbServiceProvider),
        deviceId,
      );
      if (displayFrame != null) {
        final previous = _displayFrame;
        if (previous != null && previous.rotation != displayFrame.rotation) {
          _rotationChanged = true;
        }
        _displayFrame = displayFrame;
      }
    } catch (_) {}
  }

  Future<double?> _resolveVideoAspect(String deviceId) async {
    try {
      final size = await ScrcpyFlutter.getVideoSize(deviceId: deviceId);
      if (size != null && size['width']! > 0 && size['height']! > 0) {
        final videoAspect = size['width']! / size['height']!;
        final displayFrame = _displayFrame;
        if (displayFrame != null &&
            displayFrame.isOrientationMismatch(videoAspect)) {
          _streamOrientationMismatch = true;
          return videoAspect;
        }
        return displayFrame?.chooseAspectRatio(videoAspect) ?? videoAspect;
      }
    } catch (_) {}
    return null;
  }
}
