import 'dart:convert';
import 'dart:ui';

/// Android `uiautomator dump` 输出中的单个布局节点。
class LayoutNode {
  LayoutNode(this.attributes);

  final Map<String, String> attributes;
  final List<LayoutNode> children = [];
  LayoutNode? parent;

  String get text => attributes['text'] ?? '';
  String get resourceId => attributes['resource-id'] ?? '';
  String get className => attributes['class'] ?? '';
  String get packageName => attributes['package'] ?? '';
  String get contentDesc => attributes['content-desc'] ?? '';
  String get bounds => attributes['bounds'] ?? '';
  bool get checkable => attributes['checkable'] == 'true';
  bool get checked => attributes['checked'] == 'true';
  bool get clickable => attributes['clickable'] == 'true';
  bool get enabled => attributes['enabled'] == 'true';
  bool get focusable => attributes['focusable'] == 'true';
  bool get focused => attributes['focused'] == 'true';
  bool get scrollable => attributes['scrollable'] == 'true';
  bool get longClickable => attributes['long-clickable'] == 'true';
  bool get password => attributes['password'] == 'true';
  bool get selected => attributes['selected'] == 'true';
  int get index => int.tryParse(attributes['index'] ?? '') ?? 0;

  /// 解析 `[left,top][right,bottom]` 格式的 bounds，支持越界负坐标。
  Rect? get rect {
    final b = bounds;
    if (b.isEmpty) return null;
    final regExp = RegExp(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]');
    final match = regExp.firstMatch(b);
    if (match == null) return null;

    final left = double.tryParse(match.group(1)!) ?? 0;
    final top = double.tryParse(match.group(2)!) ?? 0;
    final right = double.tryParse(match.group(3)!) ?? 0;
    final bottom = double.tryParse(match.group(4)!) ?? 0;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  String toXmlString() {
    final buffer = StringBuffer();
    _buildXmlString(buffer, 0);
    return buffer.toString();
  }

  void _buildXmlString(StringBuffer buffer, int depth) {
    final indent = '  ' * depth;
    buffer.write('$indent<node');
    attributes.forEach((key, val) {
      buffer.write(' $key="${_escapeXmlAttribute(val)}"');
    });
    if (children.isEmpty) {
      buffer.writeln(' />');
    } else {
      buffer.writeln('>');
      for (final child in children) {
        child._buildXmlString(buffer, depth + 1);
      }
      buffer.writeln('$indent</node>');
    }
  }
}

String _escapeXmlAttribute(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

/// 解析 `uiautomator dump` XML 字符串为 LayoutNode 树。
LayoutNode? parseLayoutXml(String xml) {
  final tagRegex = RegExp(r'<[^>]+>');
  final matches = tagRegex.allMatches(xml);

  LayoutNode? root;
  final stack = <LayoutNode>[];

  for (final match in matches) {
    final tagText = match.group(0)!;
    if (tagText.startsWith('</')) {
      if (stack.isNotEmpty &&
          (tagText == '</node>' || tagText == '</hierarchy>')) {
        stack.removeLast();
      }
      continue;
    }
    if (tagText.startsWith('<?')) {
      continue;
    }

    final isSelfClosing = tagText.endsWith('/>');
    final tagName = tagText.startsWith('<hierarchy') ? 'hierarchy' : 'node';
    final attributes = <String, String>{};
    final attrRegex = RegExp(r'([\w\-:]+)="([^"]*)"');

    for (final attrMatch in attrRegex.allMatches(tagText)) {
      attributes[attrMatch.group(1)!] = _unescapeXml(attrMatch.group(2)!);
    }

    final node = LayoutNode(attributes);
    if (root == null && (tagName == 'hierarchy' || tagName == 'node')) {
      root = node;
      stack.add(node);
    } else if (stack.isNotEmpty) {
      final parent = stack.last;
      node.parent = parent;
      parent.children.add(node);
      if (!isSelfClosing) {
        stack.add(node);
      }
    }
  }

  return root;
}

String _unescapeXml(String input) {
  return input
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}

/// 将 HarmonyOS `uitest dumpLayout` 的 JSON 控件树转换为共享布局节点。
LayoutNode? parseHarmonyLayoutJson(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<String, dynamic>) return null;
  return _parseHarmonyNode(decoded);
}

LayoutNode _parseHarmonyNode(Map<String, dynamic> json) {
  final rawAttributes = json['attributes'];
  final attributes = <String, String>{};
  if (rawAttributes is Map) {
    for (final entry in rawAttributes.entries) {
      attributes[entry.key.toString()] = entry.value?.toString() ?? '';
    }
  }

  // 统一为 Layout Inspector 已使用的 Android 语义字段，同时保留鸿蒙原字段供属性表展示。
  attributes['class'] = attributes['type']?.isNotEmpty == true
      ? attributes['type']!
      : 'HarmonyRoot';
  attributes['resource-id'] = attributes['id']?.isNotEmpty == true
      ? attributes['id']!
      : attributes['key'] ?? '';
  attributes['package'] = attributes['bundleName'] ?? '';
  attributes['content-desc'] = attributes['description'] ?? '';

  final node = LayoutNode(attributes);
  final children = json['children'];
  if (children is List) {
    for (final childJson in children.whereType<Map>()) {
      final child = _parseHarmonyNode(
        childJson.map((key, value) => MapEntry(key.toString(), value)),
      );
      child.parent = node;
      node.children.add(child);
    }
  }
  return node;
}
