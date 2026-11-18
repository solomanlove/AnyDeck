import 'dart:io';
import 'dart:typed_data';

import '../adb/adb_result.dart';

/// 复用 HDC 已有的命令超时、错误转换与进程回收。
typedef HdcScreenshotRun =
    Future<AdbResult> Function(List<String> args, {Duration timeout});
typedef HdcScreenshotShell =
    Future<AdbResult> Function(
      String deviceId,
      String command, {
      Duration timeout,
    });

/// 接收单次真实截图；每次请求隔离本机目录与远端文件名，避免并发串图。
///
/// [deviceId] 是 HDC 目标，[run]、[shell] 由服务注入已有命令执行器；
/// [timeout] 沿用每条命令的预算。成功返回 PNG/JPEG 字节，失败保留原错误，
/// 所有路径都会在返回前清理本机临时目录并尝试删除远端截图。
Future<Uint8List> captureHdcScreenshot(
  String deviceId, {
  required HdcScreenshotRun run,
  required HdcScreenshotShell shell,
  required Duration timeout,
}) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'anydeck_hdc_screenshot_',
  );
  final token = tempDir.path.split(Platform.pathSeparator).last;
  final remotePath = '/data/local/tmp/$token.png';
  try {
    var snapRes = await shell(
      deviceId,
      'uitest screenCap -p $remotePath',
      timeout: timeout,
    );
    if (!snapRes.isSuccess) {
      snapRes = await shell(
        deviceId,
        'snapshot_display -f $remotePath',
        timeout: timeout,
      );
    }
    if (!snapRes.isSuccess) {
      throw Exception('HarmonyOS screenshot failed: ${snapRes.message}');
    }
    final localPath = '${tempDir.path}/screenshot.png';
    final recvRes = await run([
      '-t',
      deviceId,
      'file',
      'recv',
      remotePath,
      localPath,
    ], timeout: timeout);
    final localFile = File(localPath);
    if (!recvRes.isSuccess || !await localFile.exists()) {
      throw Exception('HarmonyOS hdc file recv failed: ${recvRes.stderr}');
    }
    return await localFile.readAsBytes();
  } finally {
    // 部分接收文件也要清理；清理异常不覆盖原截图结果或错误。
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
    try {
      await shell(deviceId, 'rm $remotePath', timeout: timeout);
    } catch (_) {}
  }
}
