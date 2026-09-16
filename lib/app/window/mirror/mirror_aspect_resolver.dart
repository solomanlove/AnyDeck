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

  /// 点击投屏前，主动快速获取 Android/鸿蒙/iOS 设备当前的宽高比。
  /// 优先使用实时显示方向与尺寸，获取失败时依次回退到快速命令与缓存 overview。
  static Future<double?> fetchDeviceAspectRatioBeforeMirror({
    required WidgetRef ref,
    required String deviceId,
    required bool isHarmony,
    required bool isIos,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    if (isIos) {
      final overview = ref.read(deviceOverviewProvider(deviceId)).asData?.value;
      final res = overview?.physicalResolution;
      if (res != null && res != '-') {
        final match = RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch(res);
        if (match != null) {
          final w = int.tryParse(match.group(1)!);
          final h = int.tryParse(match.group(2)!);
          if (w != null && h != null && w > 0 && h > 0) return w / h;
        }
      }
      return null;
    }

    if (isHarmony || deviceId.startsWith('harmony:')) {
      try {
        final hdc = ref.read(hdcServiceProvider);
        final res = await hdc.shell(
          deviceId,
          'hidumper -s DisplayManagerService -a -a',
          timeout: timeout,
        );
        if (res.isSuccess && res.stdout.isNotEmpty) {
          final (w, h) = HarmonyMirrorService.parseDisplayDimensions(res.stdout);
          if (w != null && h != null && w > 0 && h > 0) {
            return w / h;
          }
        }
      } catch (_) {}

      try {
        final hdc = ref.read(hdcServiceProvider);
        final screenRes = await hdc.shell(
          deviceId,
          'hidumper -s RenderService -a screen',
          timeout: const Duration(milliseconds: 800),
        );
        if (screenRes.isSuccess && screenRes.stdout.isNotEmpty) {
          final match = RegExp(r'physical resolution=([0-9]+)x([0-9]+)').firstMatch(screenRes.stdout);
          if (match != null) {
            final w = int.tryParse(match.group(1)!);
            final h = int.tryParse(match.group(2)!);
            if (w != null && h != null && w > 0 && h > 0) {
              return w / h;
            }
          }
        }
      } catch (_) {}
    } else {
      // Android 设备
      try {
        final adb = ref.read(adbServiceProvider);
        final displayFrame = await DeviceDisplayFrame.read(
          adb,
          deviceId,
          timeout: timeout,
        );
        if (displayFrame != null && displayFrame.width > 0 && displayFrame.height > 0) {
          return displayFrame.aspectRatio;
        }
      } catch (_) {}

      try {
        final adb = ref.read(adbServiceProvider);
        final wmRes = await adb.shell(
          deviceId,
          'wm size',
          timeout: const Duration(milliseconds: 800),
        );
        if (wmRes.isSuccess && wmRes.stdout.isNotEmpty) {
          final match = RegExp(r'(?:Override|Physical) size:\s*(\d+)\s*x\s*(\d+)').firstMatch(wmRes.stdout);
          if (match != null) {
            final w = int.tryParse(match.group(1)!);
            final h = int.tryParse(match.group(2)!);
            if (w != null && h != null && w > 0 && h > 0) {
              return w / h;
            }
          }
        }
      } catch (_) {}
    }

    // 兜底：从设备 Overview 缓存中读取
    final overview = ref.read(deviceOverviewProvider(deviceId)).asData?.value;
    final res = overview?.physicalResolution;
    if (res != null && res != '-') {
      final match = RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch(res);
      if (match != null) {
        final w = int.tryParse(match.group(1)!);
        final h = int.tryParse(match.group(2)!);
        if (w != null && h != null && w > 0 && h > 0) return w / h;
      }
    }
    return null;
  }
}
