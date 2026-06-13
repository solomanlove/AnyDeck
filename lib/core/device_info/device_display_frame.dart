import '../adb/adb_service.dart';

/// Android 当前逻辑显示区域，用于修正投屏横竖屏切换后的显示比例。
class DeviceDisplayFrame {
  const DeviceDisplayFrame({
    required this.width,
    required this.height,
    required this.rotation,
  });

  final int width;
  final int height;
  final int rotation;

  double get aspectRatio {
    if (width <= 0 || height <= 0) return 9 / 16;
    return width / height;
  }

  bool get isLandscape => width > height || rotation == 1 || rotation == 3;

  bool isOrientationMismatch(double videoAspect) {
    return (isLandscape && videoAspect < 1) ||
        (!isLandscape && videoAspect > 1);
  }

  double chooseAspectRatio(double? videoAspect) {
    if (videoAspect == null || isOrientationMismatch(videoAspect)) {
      return aspectRatio;
    }
    return videoAspect;
  }

  static DeviceDisplayFrame? parseDumpsysDisplay(String output) {
    // 1. 优先匹配主屏幕的 Viewport INTERNAL，以获取最准确的屏幕尺寸和 rotation
    for (final line in output.split('\n')) {
      final listFrameMatch = RegExp(
        r'Viewport INTERNAL:.*?orientation=(\d+).*?logicalFrame=\[0, 0, (\d+), (\d+)\]',
      ).firstMatch(line);
      if (listFrameMatch != null) {
        return DeviceDisplayFrame(
          width: int.parse(listFrameMatch.group(2)!),
          height: int.parse(listFrameMatch.group(3)!),
          rotation: int.parse(listFrameMatch.group(1)!),
        );
      }

      final rectFrameMatch = RegExp(
        r'Viewport INTERNAL:.*?orientation=(\d+).*?logicalFrame=Rect\(0, 0 - (\d+), (\d+)\)',
      ).firstMatch(line);
      if (rectFrameMatch != null) {
        return DeviceDisplayFrame(
          width: int.parse(rectFrameMatch.group(2)!),
          height: int.parse(rectFrameMatch.group(3)!),
          rotation: int.parse(rectFrameMatch.group(1)!),
        );
      }
    }

    // 2. 其次匹配显式指明为主屏 (displayId 0/local:0) 的 mOverrideDisplayInfo
    for (final line in output.split('\n')) {
      if (line.contains('displayId 0') ||
          line.contains('displayId=0') ||
          line.contains('local:0')) {
        final overrideMatch = RegExp(
          r'mOverrideDisplayInfo=.*?\b(?:app|real)\s+(\d+)\s+x\s+(\d+).*?\brotation\s+(\d+)',
        ).firstMatch(line);
        if (overrideMatch != null) {
          return DeviceDisplayFrame(
            width: int.parse(overrideMatch.group(1)!),
            height: int.parse(overrideMatch.group(2)!),
            rotation: int.parse(overrideMatch.group(3)!),
          );
        }
      }
    }

    // 3. 兜底匹配任意的 mOverrideDisplayInfo，但排除虚拟屏、副屏、模拟屏的干扰
    for (final line in output.split('\n')) {
      final lowercase = line.toLowerCase();
      if (lowercase.contains('virtual') ||
          lowercase.contains('overlay') ||
          lowercase.contains('side') ||
          lowercase.contains('sub') ||
          lowercase.contains('virtual-')) {
        continue;
      }
      final overrideMatch = RegExp(
        r'mOverrideDisplayInfo=.*?\b(?:app|real)\s+(\d+)\s+x\s+(\d+).*?\brotation\s+(\d+)',
      ).firstMatch(line);
      if (overrideMatch != null) {
        return DeviceDisplayFrame(
          width: int.parse(overrideMatch.group(1)!),
          height: int.parse(overrideMatch.group(2)!),
          rotation: int.parse(overrideMatch.group(3)!),
        );
      }
    }

    return null;
  }

  static Future<DeviceDisplayFrame?> read(
    AdbService adb,
    String deviceId,
  ) async {
    final result = await adb.shell(
      deviceId,
      'dumpsys display',
      timeout: const Duration(seconds: 2),
    );
    if (!result.isSuccess) return null;
    return parseDumpsysDisplay(result.stdout);
  }
}
