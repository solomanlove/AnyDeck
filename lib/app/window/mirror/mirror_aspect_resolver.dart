import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device_info/device_display_frame.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';

/// 统一解析投屏窗口当前应该使用的横竖屏比例。
class MirrorAspectResolver {
  DeviceDisplayFrame? _displayFrame;

  Future<double> resolveNow({
    required WidgetRef ref,
    required String deviceId,
    required String? resolution,
    required double Function(String?) fallbackAspect,
  }) async {
    await _refreshDisplayFrame(ref, deviceId);
    return _resolveVideoAspect(ref, deviceId) ??
        _displayFrame?.aspectRatio ??
        fallbackAspect(resolution);
  }

  Future<void> _refreshDisplayFrame(WidgetRef ref, String deviceId) async {
    try {
      final displayFrame = await DeviceDisplayFrame.read(
        ref.read(adbServiceProvider),
        deviceId,
      );
      if (displayFrame != null) {
        _displayFrame = displayFrame;
      }
    } catch (_) {}
  }

  double? _resolveVideoAspect(WidgetRef ref, String deviceId) {
    try {
      final size = deviceId.startsWith('harmony:')
          ? ref.read(harmonyMirrorServiceProvider).getVideoSize(deviceId)
          : ref.read(embeddedScrcpyServiceProvider).getVideoSize(deviceId);
      if (size != null && size['width']! > 0 && size['height']! > 0) {
        final videoAspect = size['width']! / size['height']!;
        final displayFrame = _displayFrame;
        if (displayFrame != null &&
            displayFrame.isOrientationMismatch(videoAspect)) {
          return videoAspect;
        }
        return displayFrame?.chooseAspectRatio(videoAspect) ?? videoAspect;
      }
    } catch (_) {}
    return null;
  }
}
