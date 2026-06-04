import 'dart:async';
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
    final (parsedRoot, xmlContent) = await captureLayout(deviceId);
    final screenshotBytes = await captureScreenshot(deviceId);
    return LayoutInspectorSnapshot(
      rootNode: parsedRoot,
      xmlContent: xmlContent,
      screenshotBytes: screenshotBytes,
    );
  }

  Future<(LayoutNode, String)> captureLayout(String deviceId) async {
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

    return (parsedRoot, xmlContent);
  }

  Future<Uint8List> captureScreenshot(String deviceId) async {
    try {
      return await _adb.captureScreenshot(deviceId, timeout: _screenshotTimeout);
    } on AdbException catch (e) {
      throw LayoutInspectorException(e.message);
    }
  }

  void _throwIfFailed(AdbResult result) {
    if (!result.isSuccess) {
      throw LayoutInspectorException(result.message, result: result);
    }
  }
}
