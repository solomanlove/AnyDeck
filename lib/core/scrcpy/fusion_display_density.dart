import 'dart:async';

import '../adb/adb_service.dart';
import 'fusion_display_resize.dart';

/// 等副屏物理尺寸真正变更后再设置 DPI，避免 VirtualDisplay.resize 覆盖较早的 wm density。
class FusionDisplayDensity {
  static Future<bool> applyWhenResized({
    required AdbService adbService,
    required String deviceId,
    required int displayId,
    required FusionDisplayGeometry geometry,
    bool Function()? isCurrent,
  }) async {
    final deadline = Stopwatch()..start();
    final expectedWidth = geometry.width.toString();
    final expectedHeight = geometry.height.toString();
    final physicalSize = RegExp(r'Physical size:\s*(\d+)x(\d+)');
    while (true) {
      if (isCurrent != null && !isCurrent()) return false;
      final size = await adbService.shellArgs(
        deviceId,
        ['wm', 'size', '-d', '$displayId'],
        timeout: const Duration(seconds: 1),
      );
      final match = physicalSize.firstMatch(size.stdout);
      if (size.isSuccess &&
          match?.group(1) == expectedWidth &&
          match?.group(2) == expectedHeight) {
        break;
      }
      if (deadline.elapsed >= const Duration(seconds: 3)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (isCurrent != null && !isCurrent()) return false;
    final density = await adbService.shellArgs(
      deviceId,
      ['wm', 'density', '${geometry.densityDpi}', '-d', '$displayId'],
      timeout: const Duration(seconds: 4),
    );
    return density.isSuccess && !density.message.startsWith('Error:');
  }
}
