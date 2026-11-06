import 'dart:async';
import 'dart:convert';

import '../adb/adb_service.dart';
import 'activity_escape_guardian.dart';

/// 在 scrcpy 虚拟副屏创建后放置指定 App，确保首帧等待不会和 App 迁移互相阻塞。
Future<Timer> launchAppOnVirtualDisplay({
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
      return startActivityEscapeGuardian(adbService, deviceId, packageName, displayId);
    }
  }

  // App 尚无 Task 时解析 LAUNCHER Activity，再显式启动；部分 ROM 不解析仅指定包名的 Intent。
  final component = await resolveAppLauncherComponent(
    adbService,
    deviceId,
    packageName,
  );
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
    '-n',
    component,
    '--display',
    displayId.toString(),
    '-f',
    '0x10000000',
  ];
  final startResult = await adbService.run(startArguments);
  if (!startResult.isSuccess || startResult.stdout.contains('Error:')) {
    final message = startResult.stderr.trim().isNotEmpty
        ? startResult.stderr.trim()
        : startResult.stdout.trim();
    throw Exception(
      'Failed to launch $packageName on display $displayId: $message',
    );
  }

  // 覆盖开屏广告或页面跳转逃回主屏的短暂窗口。
  return startActivityEscapeGuardian(adbService, deviceId, packageName, displayId);
}

/// 普通模式显式把既有 Task 移回主屏，再把目标 App 拉到前台。
Future<void> launchAppOnPrimaryDisplay({
  required AdbService adbService,
  required String deviceId,
  required String packageName,
}) async {
  final taskList = await adbService.shellArgs(
    deviceId,
    ['cmd', 'activity', 'stack', 'list'],
  );
  final rootTaskId = taskList.isSuccess
      ? findRootTaskId(taskList.stdout, packageName)
      : null;
  final rootDisplayId = taskList.isSuccess
      ? findRootTaskDisplayId(taskList.stdout, packageName)
      : null;
  if (rootTaskId != null && rootDisplayId != 0) {
    final move = await adbService.shellArgs(
      deviceId,
      ['cmd', 'activity', 'display', 'move-stack', '$rootTaskId', '0'],
    );
    if (!move.isSuccess) {
      throw StateError('Failed to move $packageName to display 0: ${move.message}');
    }
  }
  final component = await resolveAppLauncherComponent(
    adbService,
    deviceId,
    packageName,
  );
  final start = await adbService.shellArgs(deviceId, [
    'am', 'start',
    '-a', 'android.intent.action.MAIN',
    '-c', 'android.intent.category.LAUNCHER',
    '-n', component,
    '--display', '0',
    '-f', '0x10000000',
  ]);
  if (!start.isSuccess || start.stdout.contains('Error:')) {
    throw StateError('Failed to launch $packageName on display 0: ${start.message}');
  }
}

/// 按当前用户解析应用的 LAUNCHER Activity，避免厂商 ROM 拒绝隐式包名 Intent。
Future<String> resolveAppLauncherComponent(
  AdbService adbService,
  String deviceId,
  String packageName,
) async {
  final result = await adbService.shellArgs(deviceId, [
    'cmd', 'package', 'resolve-activity', '--brief', '--user', 'current',
    '-a', 'android.intent.action.MAIN',
    '-c', 'android.intent.category.LAUNCHER',
    '-p', packageName,
  ]);
  if (result.isSuccess) {
    for (final line in const LineSplitter().convert(result.stdout).reversed) {
      final component = line.trim();
      final prefix = '$packageName/';
      if (component.startsWith(prefix) &&
          RegExp(r'^[A-Za-z0-9_.$]+$')
              .hasMatch(component.substring(prefix.length))) {
        return component;
      }
    }
  }
  throw StateError(
    '应用 $packageName 没有可启动的主界面：${result.message}',
  );
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

/// 返回目标 App 所在 RootTask 的 display ID，避免对主屏 Task 重复迁移。
int? findRootTaskDisplayId(String output, String packageName) {
  int? currentDisplayId;
  final packageTaskPattern = RegExp(
    r'taskId=\d+:\s+' + RegExp.escape(packageName) + r'/',
  );
  for (final line in const LineSplitter().convert(output)) {
    if (RegExp(r'^\s*RootTask id=\d+\b').hasMatch(line)) {
      currentDisplayId = int.tryParse(
        RegExp(r'\bdisplayId=(\d+)').firstMatch(line)?.group(1) ?? '',
      );
    } else if (packageTaskPattern.hasMatch(line)) {
      return currentDisplayId;
    }
  }
  return null;
}
