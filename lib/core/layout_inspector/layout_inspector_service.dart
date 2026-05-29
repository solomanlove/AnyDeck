import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import 'layout_node.dart';

/// 一次布局分析抓取结果，包含 XML 树和原始截图字节。
class LayoutInspectorSnapshot {
  const LayoutInspectorSnapshot({
    required this.rootNode,
    required this.xmlContent,
    required this.screenshotBytes,
  });

  final LayoutNode rootNode;
  final String xmlContent;
  final Uint8List screenshotBytes;
}

/// 带 ADB 执行结果的布局分析异常，便于 UI 同步断开状态。
class LayoutInspectorException implements Exception {
  const LayoutInspectorException(this.message, {this.result});

  final String message;
  final AdbResult? result;

  @override
  String toString() => message;
}

/// 负责从 Android 设备抓取 `uiautomator` XML 和屏幕截图。
class LayoutInspectorService {
  const LayoutInspectorService(this._adb);

  static const _screenshotTimeout = Duration(seconds: 15);

  final AdbService _adb;

  Future<LayoutInspectorSnapshot> capture(String deviceId) async {
    final dumpResult = await _adb.shellArgs(deviceId, [
      'uiautomator',
      'dump',
      '/data/local/tmp/uidump.xml',
    ]);
    _throwIfFailed(dumpResult);

    final catResult = await _adb.shellArgs(deviceId, [
      'cat',
      '/data/local/tmp/uidump.xml',
    ]);
    _throwIfFailed(catResult);

    final xmlContent = catResult.stdout;
    final parsedRoot = parseLayoutXml(xmlContent);
    if (parsedRoot == null) {
      throw const LayoutInspectorException('XML 解析失败或内容为空');
    }

    return LayoutInspectorSnapshot(
      rootNode: parsedRoot,
      xmlContent: xmlContent,
      screenshotBytes: await _captureScreenshot(deviceId),
    );
  }

  Future<Uint8List> _captureScreenshot(String deviceId) async {
    Process? process;
    try {
      process = await Process.start(_adb.executable, [
        '-s',
        deviceId,
        'exec-out',
        'screencap',
        '-p',
      ]);
      final stdoutFuture = process.stdout.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      final stderrFuture = process.stderr
          .transform(systemEncoding.decoder)
          .join();
      final exitCode = await process.exitCode.timeout(_screenshotTimeout);
      final stderr = await stderrFuture;
      if (exitCode != 0) {
        final adbResult = AdbResult(
          exitCode: exitCode,
          stdout: '',
          stderr: stderr,
        );
        throw LayoutInspectorException(adbResult.message, result: adbResult);
      }

      return Uint8List.fromList(await stdoutFuture);
    } on TimeoutException {
      process?.kill();
      await process?.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process?.kill(ProcessSignal.sigkill);
          return 124;
        },
      );
      final adbResult = AdbResult(
        exitCode: 124,
        stdout: '',
        stderr: 'adb截图命令超时(${_screenshotTimeout.inSeconds}s)',
      );
      throw LayoutInspectorException(adbResult.message, result: adbResult);
    } on ProcessException catch (error) {
      final adbResult = AdbResult(
        exitCode: 127,
        stdout: '',
        stderr: error.message,
      );
      throw LayoutInspectorException(adbResult.message, result: adbResult);
    }
  }

  void _throwIfFailed(AdbResult result) {
    if (!result.isSuccess) {
      throw LayoutInspectorException(result.message, result: result);
    }
  }
}
