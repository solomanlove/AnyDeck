import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device_info/device_display_frame.dart';
import '../../../core/harmony/harmony_mirror_service.dart';
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
    final isHarmony = deviceId.startsWith('harmony:') ||
        ref.read(harmonyMirrorServiceProvider).isActive(deviceId) ||
        ref.read(deviceRegistryProvider).any((d) => d.id == deviceId && d.isHarmony);
    if (isHarmony) {
      try {
        final res = await ref.read(hdcServiceProvider).shell(
          deviceId,
          'hidumper -s DisplayManagerService -a -a',
        );
        if (res.isSuccess && res.stdout.isNotEmpty) {
          final (w, h) = HarmonyMirrorService.parseDisplayDimensions(res.stdout);
          if (w != null && h != null && w > 0 && h > 0) {
            _displayFrame = DeviceDisplayFrame(
              width: w,
              height: h,
              rotation: w >= h ? 1 : 0,
            );
          }
        }
      } catch (_) {}
      return;
    }
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
      final isHarmony = deviceId.startsWith('harmony:') ||
          ref.read(harmonyMirrorServiceProvider).isActive(deviceId) ||
          ref.read(deviceRegistryProvider).any((d) => d.id == deviceId && d.isHarmony);
      final size = isHarmony
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
