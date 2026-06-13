import 'package:flutter/material.dart';

import '../../../../core/device_info/device_display_frame.dart';

/// scrcpy 视频画面在 Flutter 容器中的比例、尺寸和触控坐标换算工具。
class ScrcpyVideoGeometry {
  const ScrcpyVideoGeometry._();

  static double resolveAspectRatio(String? resolutionStr) {
    if (resolutionStr == null || resolutionStr == '-') return 9 / 16;
    final match = RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch(resolutionStr);
    if (match != null) {
      final w = int.parse(match.group(1)!);
      final h = int.parse(match.group(2)!);
      if (w > 0 && h > 0) {
        return w / h;
      }
    }
    return 9 / 16;
  }

  static Size fitTextureSize(Size maxSize, double aspectRatio) {
    if (maxSize.width <= 0 ||
        maxSize.height <= 0 ||
        aspectRatio <= 0 ||
        aspectRatio.isNaN ||
        aspectRatio.isInfinite) {
      return Size.zero;
    }

    final containerRatio = maxSize.width / maxSize.height;
    if (containerRatio > aspectRatio) {
      return Size(maxSize.height * aspectRatio, maxSize.height);
    }
    return Size(maxSize.width, maxSize.width / aspectRatio);
  }

  static double resolveDisplayAwareAspectRatio({
    required int? videoWidth,
    required int? videoHeight,
    required DeviceDisplayFrame? displayFrame,
    required String? fallbackResolution,
  }) {
    final videoAspect =
        videoWidth != null &&
            videoHeight != null &&
            videoWidth > 0 &&
            videoHeight > 0
        ? videoWidth / videoHeight
        : null;

    if (displayFrame != null &&
        (videoAspect == null ||
            !displayFrame.isOrientationMismatch(videoAspect))) {
      return displayFrame.chooseAspectRatio(videoAspect);
    }

    return videoAspect ?? resolveAspectRatio(fallbackResolution);
  }

  static List<int> resolveVideoSize({
    required String? resolution,
    required Size fallbackSize,
    required int? videoWidth,
    required int? videoHeight,
  }) {
    int realW = videoWidth ?? fallbackSize.width.toInt();
    int realH = videoHeight ?? fallbackSize.height.toInt();

    if (videoWidth == null || videoHeight == null) {
      if (resolution != null && resolution != '-') {
        final match = RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch(resolution);
        if (match != null) {
          final w = int.parse(match.group(1)!);
          final h = int.parse(match.group(2)!);
          if (w > 0 && h > 0) {
            realW = w;
            realH = h;
          }
        }
      }
    }

    return [realW, realH];
  }

  static List<int>? mapPointerToVideo({
    required PointerEvent event,
    required RenderBox renderBox,
    required String? resolution,
    required int? videoWidth,
    required int? videoHeight,
  }) {
    final size = renderBox.size;
    if (size.width <= 0 || size.height <= 0) return null;

    final localPosition = renderBox.globalToLocal(event.position);
    final videoSize = resolveVideoSize(
      resolution: resolution,
      fallbackSize: size,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
    );
    final realW = videoSize[0];
    final realH = videoSize[1];
    if (realW <= 0 || realH <= 0) return null;

    final x = (localPosition.dx / size.width * realW)
        .clamp(0.0, realW.toDouble())
        .toInt();
    final y = (localPosition.dy / size.height * realH)
        .clamp(0.0, realH.toDouble())
        .toInt();

    return [x, y, realW, realH];
  }
}
