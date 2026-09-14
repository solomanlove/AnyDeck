import 'dart:async';
import 'dart:io';

import '../adb/adb_service.dart';

/// 启动后台守护轮询，防范 Activity 在跳转时逃逸回主屏幕（Display 0）。
///
/// 轮询持续 12 秒，每 500 毫秒检查一次，主要覆盖开屏广告与主页面过渡期。
void startActivityEscapeGuardian(
  AdbService adbService,
  String deviceId,
  String packageName,
  int targetDisplayId,
) {
  int count = 0;
  Timer.periodic(const Duration(milliseconds: 500), (timer) async {
    count++;
    if (count > 24) {
      timer.cancel();
      return;
    }

    try {
      final res = await adbService.run([
        '-s',
        deviceId,
        'shell',
        'am',
        'stack',
        'list',
      ]);
      if (!res.isSuccess) return;

      final lines = res.stdout.split('\n');
      String? currentStackId;
      String? currentDisplayId;

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('Stack id=') || trimmed.startsWith('RootTask id=')) {
          final stackMatch = RegExp(r'(?:Stack|RootTask)\s+id=(\d+)').firstMatch(trimmed);
          final displayMatch = RegExp(r'displayId=(\d+)').firstMatch(trimmed);
          if (stackMatch != null) {
            currentStackId = stackMatch.group(1);
          } else {
            currentStackId = null;
          }
          if (displayMatch != null) {
            currentDisplayId = displayMatch.group(1);
          } else {
            currentDisplayId = null;
          }
        } else if (trimmed.startsWith('taskId=')) {
          if (currentStackId != null && currentDisplayId == '0') {
            if (trimmed.contains(packageName)) {
              final moveRes = await adbService.run([
                '-s',
                deviceId,
                'shell',
                'am',
                'display',
                'move-stack',
                currentStackId,
                targetDisplayId.toString(),
              ]);
              if (moveRes.isSuccess) {
                stdout.write(
                  '[EscapeGuardian] Successfully moved escaped stack $currentStackId of $packageName back to display $targetDisplayId\n',
                );
              }
              break;
            }
          }
        }
      }
    } catch (_) {
      // Ignored
    }
  });
}
