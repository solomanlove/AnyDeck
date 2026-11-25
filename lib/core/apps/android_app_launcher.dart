import 'dart:convert';

import '../adb/adb_service.dart';

/// 解析指定 Android 用户的 LAUNCHER Activity，省略用户时沿用当前用户。
Future<String> resolveAppLauncherComponent(
  AdbService adbService,
  String deviceId,
  String packageName, {
  int? userId,
}) async {
  final result = await adbService.shellArgs(deviceId, [
    'cmd',
    'package',
    'resolve-activity',
    '--brief',
    '--user',
    userId?.toString() ?? 'current',
    '-a',
    'android.intent.action.MAIN',
    '-c',
    'android.intent.category.LAUNCHER',
    '-p',
    packageName,
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
  final user = userId == null ? '' : '在 Android 用户 $userId 下';
  throw StateError('应用 $packageName $user没有可启动的主界面：${result.message}');
}
