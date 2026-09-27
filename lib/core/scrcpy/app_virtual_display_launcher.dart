import 'dart:async';

import '../adb/adb_service.dart';
import 'activity_escape_guardian.dart';

/// 在 scrcpy 虚拟副屏创建后启动指定 App，确保首帧等待不会和 App 启动互相阻塞。
Future<void> launchAppOnVirtualDisplay({
  required AdbService adbService,
  required String deviceId,
  required String packageName,
  required Future<int> displayIdFuture,
}) async {
  final displayId = await displayIdFuture.timeout(const Duration(seconds: 10));

  await adbService.run([
    '-s',
    deviceId,
    'shell',
    'am',
    'force-stop',
    packageName,
  ]);

  // 使用 package Intent，避免 Activity alias 中的 `$` 被设备端 adb shell 当作变量展开。
  final startArguments = <String>[
    '-s',
    deviceId,
    'shell',
    'am',
    'start',
    '-a',
    'android.intent.action.MAIN',
    '-c',
    'android.intent.category.LAUNCHER',
    '-p',
    packageName,
    '--display',
    displayId.toString(),
    '-f',
    '0x10000000',
  ];
  final startResult = await adbService.run(startArguments);
  if (!startResult.isSuccess) {
    final message = startResult.stderr.trim().isNotEmpty
        ? startResult.stderr.trim()
        : startResult.stdout.trim();
    throw Exception(
      'Failed to launch $packageName on display $displayId: $message',
    );
  }

  // 覆盖开屏广告或页面跳转逃回主屏的短暂窗口。
  startActivityEscapeGuardian(adbService, deviceId, packageName, displayId);
}
