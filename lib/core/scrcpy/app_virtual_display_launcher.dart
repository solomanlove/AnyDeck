import 'dart:async';
import 'dart:convert';

import '../adb/adb_service.dart';
import 'activity_escape_guardian.dart';

/// 在 scrcpy 虚拟副屏创建后放置指定 App，确保首帧等待不会和 App 迁移互相阻塞。
Future<void> launchAppOnVirtualDisplay({
  required AdbService adbService,
  required String deviceId,
  required String packageName,
  required Future<int> displayIdFuture,
}) async {
  final displayId = await displayIdFuture.timeout(const Duration(seconds: 10));

  // 已存在的 Task 直接迁移到虚拟副屏，保留 PID、Activity back stack 和页面状态。
  final taskList = await adbService.run([
    '-s',
    deviceId,
    'shell',
    'cmd',
    'activity',
    'stack',
    'list',
  ]);
  final rootTaskId = taskList.isSuccess
      ? findRootTaskId(taskList.stdout, packageName)
      : null;
  if (rootTaskId != null) {
    final moveResult = await adbService.run([
      '-s',
      deviceId,
      'shell',
      'cmd',
      'activity',
      'display',
      'move-stack',
      rootTaskId.toString(),
      displayId.toString(),
    ]);
    if (moveResult.isSuccess) {
      startActivityEscapeGuardian(adbService, deviceId, packageName, displayId);
      return;
    }
  }

  // App 尚无 Task 时才通过 package Intent 启动，避免刷新时重建已有页面。
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

/// 从 `cmd activity stack list` 中找到包名所属的 RootTask。
int? findRootTaskId(String output, String packageName) {
  int? currentRootTaskId;
  final packageTaskPattern = RegExp(
    r'taskId=\d+:\s+' + RegExp.escape(packageName) + r'/',
  );
  for (final line in const LineSplitter().convert(output)) {
    final rootTaskMatch = RegExp(r'^\s*RootTask id=(\d+)\b').firstMatch(line);
    if (rootTaskMatch != null) {
      currentRootTaskId = int.tryParse(rootTaskMatch.group(1)!);
      continue;
    }
    if (currentRootTaskId != null && packageTaskPattern.hasMatch(line)) {
      return currentRootTaskId;
    }
  }
  return null;
}
