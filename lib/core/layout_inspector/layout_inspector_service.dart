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
    try {
      final result = await Process.run(_adb.executable, [
        '-s',
        deviceId,
        'exec-out',
        'screencap',
        '-p',
      ], stdoutEncoding: null);
      if (result.exitCode != 0) {
        final adbResult = AdbResult(
          exitCode: result.exitCode,
          stdout: result.stdout is String ? result.stdout.toString() : '',
          stderr: result.stderr.toString(),
        );
        throw LayoutInspectorException(adbResult.message, result: adbResult);
      }

      final stdout = result.stdout;
      if (stdout is List<int>) {
        return Uint8List.fromList(stdout);
      }

      throw const LayoutInspectorException('截图输出格式异常');
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
