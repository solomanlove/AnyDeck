import 'package:xml/xml.dart';

import '../layout_inspector/layout_node.dart';
import 'ios_command_service.dart';

/// 将 WDA Accessibility 树转换为截图页共用的布局节点。
class IosLayoutService {
  IosLayoutService(this._commands);

  final IosCommandService _commands;

  Future<(LayoutNode, String)> capture(
    String udid, {
    required int imageWidth,
    required int imageHeight,
  }) async {
    final geometryResult = await _commands.automationGeometry(udid);
    if (!geometryResult.isSuccess) throw StateError(geometryResult.message);
    final source = await _commands.automationSource(udid);
    if (!source.isSuccess) throw StateError(source.message);
    final geometry = _commands.parseAutomationValue(geometryResult.stdout);
    final rawSource = _commands.parseAutomationValue(source.stdout)['value'];
    if (rawSource is! String || rawSource.trim().isEmpty) {
      throw const FormatException('WDA UI Source 为空');
    }
    final width = geometry['width'];
    final height = geometry['height'];
    if (width is! num || height is! num || width <= 0 || height <= 0) {
      throw const FormatException('WDA 未返回有效屏幕尺寸');
    }
    final root = parseIosLayoutXml(
      rawSource,
      scaleX: imageWidth / width,
      scaleY: imageHeight / height,
    );
    return (root, root.toXmlString());
  }
}

/// 保留 iOS 原始属性，同时提供共享画布所需的像素 bounds。
LayoutNode parseIosLayoutXml(
  String source, {
  required double scaleX,
  required double scaleY,
}) {
  if (!scaleX.isFinite || !scaleY.isFinite || scaleX <= 0 || scaleY <= 0) {
    throw const FormatException('iOS 布局缩放比例无效');
  }
  final document = XmlDocument.parse(source);
  final element = document.rootElement;

  LayoutNode convert(XmlElement xml, int index) {
    final attributes = <String, String>{
      'class': xml.name.local,
      'index': '$index',
      for (final item in xml.attributes) item.name.local: item.value,
    };
    attributes['text'] = attributes['value'] ?? attributes['label'] ?? '';
    attributes['resource-id'] = attributes['name'] ?? '';
    attributes['content-desc'] = attributes['label'] ?? '';
    final x = double.tryParse(attributes['x'] ?? '');
    final y = double.tryParse(attributes['y'] ?? '');
    final width = double.tryParse(attributes['width'] ?? '');
    final height = double.tryParse(attributes['height'] ?? '');
    if (x != null &&
        y != null &&
        width != null &&
        height != null &&
        width >= 0 &&
        height >= 0) {
      final left = (x * scaleX).round();
      final top = (y * scaleY).round();
      final right = ((x + width) * scaleX).round();
      final bottom = ((y + height) * scaleY).round();
      attributes['bounds'] = '[$left,$top][$right,$bottom]';
    }
    final node = LayoutNode(attributes);
    var childIndex = 0;
    for (final child in xml.children.whereType<XmlElement>()) {
      final parsed = convert(child, childIndex++);
      parsed.parent = node;
      node.children.add(parsed);
    }
    return node;
  }

  return convert(element, 0);
}
