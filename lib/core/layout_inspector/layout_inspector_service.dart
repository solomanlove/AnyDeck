import 'dart:async';
import 'dart:typed_data';

import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import '../harmony/hdc_service.dart';
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

/// 负责从 Android/HarmonyOS 设备抓取控件树和屏幕截图。
class LayoutInspectorService {
  const LayoutInspectorService(
    this._adb, {
    HdcService? hdc,
    bool Function(String deviceId)? isHarmonyResolver,
  }) : _hdc = hdc,
       _isHarmonyResolver = isHarmonyResolver;

  static const _screenshotTimeout = Duration(seconds: 15);

  final AdbService _adb;
  final HdcService? _hdc;
  final bool Function(String deviceId)? _isHarmonyResolver;

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
    if (_isHarmonyResolver?.call(deviceId) == true) {
      return _captureHarmonyLayout(deviceId);
    }
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

  Future<(LayoutNode, String)> _captureHarmonyLayout(String deviceId) async {
    final hdc = _hdc;
    if (hdc == null) {
      throw const LayoutInspectorException('HarmonyOS 布局分析服务不可用');
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final remotePath = '/data/local/tmp/anydeck_layout_$timestamp.json';
    try {
      final dumpResult = await hdc.shell(
        deviceId,
        'uitest dumpLayout -p $remotePath',
        timeout: const Duration(seconds: 15),
      );
      _throwIfFailed(dumpResult);

      final catResult = await hdc.shell(
        deviceId,
        'cat $remotePath',
        timeout: const Duration(seconds: 15),
      );
      _throwIfFailed(catResult);

      final parsedRoot = parseHarmonyLayoutJson(catResult.stdout);
      if (parsedRoot == null) {
        throw const LayoutInspectorException('HarmonyOS 布局解析失败或内容为空');
      }
      // 统一导出为 XML，继续复用现有复制、导出和节点查看能力。
      return (parsedRoot, parsedRoot.toXmlString());
    } on FormatException catch (error) {
      throw LayoutInspectorException('HarmonyOS 布局 JSON 解析失败: $error');
    } finally {
      await hdc.shell(deviceId, 'rm $remotePath');
    }
  }

  Future<Uint8List> captureScreenshot(String deviceId) async {
    if (_isHarmonyResolver?.call(deviceId) == true) {
      final hdc = _hdc;
      if (hdc == null) {
        throw const LayoutInspectorException('HarmonyOS 截图服务不可用');
      }
      try {
        return await hdc.captureScreenshot(
          deviceId,
          timeout: _screenshotTimeout,
        );
      } catch (error) {
        throw LayoutInspectorException(error.toString());
      }
    }
    try {
      return await _adb.captureScreenshot(
        deviceId,
        timeout: _screenshotTimeout,
      );
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
