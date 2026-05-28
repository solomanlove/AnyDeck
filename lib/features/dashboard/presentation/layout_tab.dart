import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/adb/adb_device.dart';
import '../../../core/providers/app_providers.dart';
import 'layout_screen_preview.dart';
import 'layout_hierarchy_tree.dart';
import 'layout_properties_table.dart';

/// 表示 Android 界面布局节点的数据模型。
class LayoutNode {
  final Map<String, String> attributes;
  final List<LayoutNode> children = [];
  LayoutNode? parent;

  LayoutNode(this.attributes);

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

  /// 解析 bounds 字符串，返回 Rect。
  /// bounds 格式通常为：[left,top][right,bottom] (例如 [0,150][1220,2604])
  Rect? get rect {
    final b = bounds;
    if (b.isEmpty) return null;
    final regExp = RegExp(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]');
    final match = regExp.firstMatch(b);
    if (match != null) {
      final left = double.tryParse(match.group(1)!) ?? 0;
      final top = double.tryParse(match.group(2)!) ?? 0;
      final right = double.tryParse(match.group(3)!) ?? 0;
      final bottom = double.tryParse(match.group(4)!) ?? 0;
      return Rect.fromLTRB(left, top, right, bottom);
    }
    return null;
  }
}

/// 辅助函数：反转义 XML 实体。
String _unescapeXml(String input) {
  return input
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}

/// 解析 uiautomator dump XML 字符串为 LayoutNode 树。
LayoutNode? parseLayoutXml(String xml) {
  final tagRegex = RegExp(r'<[^>]+>');
  final matches = tagRegex.allMatches(xml);

  LayoutNode? root;
  final List<LayoutNode> stack = [];

  for (final match in matches) {
    final tagText = match.group(0)!;
    if (tagText.startsWith('</')) {
      if (stack.isNotEmpty && (tagText == '</node>' || tagText == '</hierarchy>')) {
        stack.removeLast();
      }
    } else if (tagText.startsWith('<?')) {
      continue;
    } else {
      final isSelfClosing = tagText.endsWith('/>');
      final tagName = tagText.startsWith('<hierarchy') ? 'hierarchy' : 'node';

      final Map<String, String> attributes = {};
      final attrRegex = RegExp(r'([\w\-:]+)="([^"]*)"');
      for (final attrMatch in attrRegex.allMatches(tagText)) {
        attributes[attrMatch.group(1)!] = _unescapeXml(attrMatch.group(2)!);
      }

      final node = LayoutNode(attributes);
      if (root == null && tagName == 'hierarchy') {
        root = node;
        stack.add(node);
      } else if (root == null && tagName == 'node') {
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
  }
  return root;
}

class LayoutTab extends ConsumerStatefulWidget {
  final AdbDevice device;

  const LayoutTab({super.key, required this.device});

  @override
  ConsumerState<LayoutTab> createState() => _LayoutTabState();
}

class _LayoutTabState extends ConsumerState<LayoutTab> {
  bool _loading = false;
  String? _error;
  LayoutNode? _rootNode;
  ui.Image? _decodedImage;
  LayoutNode? _selectedNode;
  LayoutNode? _hoveredNode;

  @override
  void initState() {
    super.initState();
    _loadLayoutAndScreenshot();
  }

  @override
  void didUpdateWidget(covariant LayoutTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      _loadLayoutAndScreenshot();
    }
  }

  Future<void> _loadLayoutAndScreenshot() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _rootNode = null;
      _decodedImage = null;
      _selectedNode = null;
      _hoveredNode = null;
    });

    try {
      final adb = ref.read(adbServiceProvider);

      // 1. 获取布局 XML
      final dumpResult = await adb.shellArgs(
        widget.device.id,
        ['uiautomator', 'dump', '/data/local/tmp/uidump.xml'],
      );
      if (!dumpResult.isSuccess) {
        throw Exception(dumpResult.message);
      }

      final catResult = await adb.shellArgs(
        widget.device.id,
        ['cat', '/data/local/tmp/uidump.xml'],
      );
      if (!catResult.isSuccess) {
        throw Exception(catResult.message);
      }

      final xmlContent = catResult.stdout;
      final parsedRoot = parseLayoutXml(xmlContent);
      if (parsedRoot == null) {
        throw Exception('XML 解析失败或内容为空');
      }

      // 2. 获取屏幕截图字节流
      final result = await Process.run(
        adb.executable,
        ['-s', widget.device.id, 'exec-out', 'screencap', '-p'],
        stdoutEncoding: null,
      );
      if (result.exitCode != 0) {
        throw Exception(result.stderr ?? '获取截图失败');
      }
      final bytes = Uint8List.fromList(result.stdout as List<int>);

      // 3. 解码图片以获取真实宽度和高度
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      final decodedImg = frameInfo.image;

      if (mounted) {
        setState(() {
          _rootNode = parsedRoot;
          _decodedImage = decodedImg;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _selectNode(LayoutNode? node) {
    setState(() {
      _selectedNode = node;
    });
  }

  void _hoverNode(LayoutNode? node) {
    setState(() {
      _hoveredNode = node;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(context.l10n.t('dumpingLayout')),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                '${context.l10n.t('getLayoutFailed')}\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadLayoutAndScreenshot,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.t('refreshLayout')),
              ),
            ],
          ),
        ),
      );
    }

    if (_rootNode == null || _decodedImage == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: _loadLayoutAndScreenshot,
          icon: const Icon(Icons.refresh),
          label: Text(context.l10n.t('refreshLayout')),
        ),
      );
    }

    return Column(
      children: [
        // 顶部操作区
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                context.l10n.t('layout'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              IconButton.filledTonal(
                onPressed: _loadLayoutAndScreenshot,
                tooltip: context.l10n.t('refreshLayout'),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        // 主内容区分裂视图
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 左侧树状节点结构
              Expanded(
                flex: 4,
                child: LayoutHierarchyTree(
                  rootNode: _rootNode!,
                  selectedNode: _selectedNode,
                  hoveredNode: _hoveredNode,
                  onNodeSelected: _selectNode,
                  onNodeHovered: _hoverNode,
                ),
              ),
              VerticalDivider(
                width: 1,
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
              // 2. 中间截图与选区
              Expanded(
                flex: 4,
                child: LayoutScreenPreview(
                  rootNode: _rootNode!,
                  decodedImage: _decodedImage!,
                  selectedNode: _selectedNode,
                  hoveredNode: _hoveredNode,
                  onNodeSelected: _selectNode,
                  onNodeHovered: _hoverNode,
                ),
              ),
              VerticalDivider(
                width: 1,
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
              // 3. 右侧属性详细面板
              Expanded(
                flex: 4,
                child: LayoutPropertiesTable(
                  selectedNode: _selectedNode,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
