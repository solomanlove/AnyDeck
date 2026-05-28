import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';

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

  // 增强功能状态变量
  String? _xmlContent;
  Uint8List? _rawScreenshotBytes;
  bool _showProperties = true;
  bool _showBorders = false;
  int _rotationAngle = 0;
  final Set<LayoutNode> _expandedNodes = {};
  final TransformationController _transformationController = TransformationController();
  Size _lastViewportSize = const Size(400, 800);

  @override
  void initState() {
    super.initState();
    _loadLayoutAndScreenshot();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
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
    final isFirstLoad = _rootNode == null;
    setState(() {
      _loading = true;
      _error = null;
      _selectedNode = null;
      _hoveredNode = null;
      if (isFirstLoad) {
        _rootNode = null;
        _decodedImage = null;
        _xmlContent = null;
        _rawScreenshotBytes = null;
        _rotationAngle = 0;
        _expandedNodes.clear();
        _transformationController.value = Matrix4.identity();
      }
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
          _xmlContent = xmlContent;
          _rawScreenshotBytes = bytes;
          _expandAll(parsedRoot); // 默认展开全部
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
      if (node != null) {
        _expandAncestors(node);
      }
    });
  }

  void _hoverNode(LayoutNode? node) {
    setState(() {
      _hoveredNode = node;
    });
  }

  // XML 节点展开与折叠辅助函数
  void _expandAll(LayoutNode node) {
    _expandedNodes.add(node);
    for (final child in node.children) {
      _expandAll(child);
    }
  }

  void _expandAllNodes() {
    if (_rootNode == null) return;
    setState(() {
      _expandAll(_rootNode!);
    });
  }

  void _collapseAllNodes() {
    setState(() {
      _expandedNodes.clear();
      if (_rootNode != null) {
        _expandedNodes.add(_rootNode!);
      }
    });
  }

  void _expandAncestors(LayoutNode node) {
    var current = node.parent;
    while (current != null) {
      _expandedNodes.add(current);
      current = current.parent;
    }
  }

  // 复制与保存逻辑
  void _copyNodeXml() {
    final node = _selectedNode ?? _rootNode;
    if (node == null) return;

    final buffer = StringBuffer();
    _buildNodeXmlString(node, buffer, 0);
    final xmlText = buffer.toString();

    Clipboard.setData(ClipboardData(text: xmlText));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.t('copySuccess')),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xff09c47c),
        behavior: SnackBarBehavior.floating,
        width: 300,
      ),
    );
  }

  void _buildNodeXmlString(LayoutNode node, StringBuffer buffer, int depth) {
    final indent = '  ' * depth;
    buffer.write('$indent<node');
    node.attributes.forEach((key, val) {
      buffer.write(' $key="${val.replaceAll('"', '&quot;')}"');
    });
    if (node.children.isEmpty) {
      buffer.writeln(' />');
    } else {
      buffer.writeln('>');
      for (final child in node.children) {
        _buildNodeXmlString(child, buffer, depth + 1);
      }
      buffer.writeln('$indent</node>');
    }
  }

  Future<void> _saveLayoutAndScreenshot() async {
    if (_rawScreenshotBytes == null || _xmlContent == null) return;

    try {
      final location = await getSaveLocation(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PNG Image', extensions: ['png']),
        ],
        suggestedName: 'layout_${widget.device.id}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      if (location == null) return;

      final basePath = location.path;
      final pngFile = File(basePath);
      await pngFile.writeAsBytes(_rawScreenshotBytes!);

      final xmlPath = '${basePath.replaceAll(RegExp(r'\.png$', caseSensitive: false), '')}.xml';
      final xmlFile = File(xmlPath);
      await xmlFile.writeAsString(_xmlContent!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功保存截图与 XML 至: $basePath'),
            backgroundColor: const Color(0xff09c47c),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // 缩放、平移和重置控制
  void _zoom(double factor) {
    final currentMatrix = _transformationController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    if (currentScale * factor < 0.1 || currentScale * factor > 10.0) return;

    final center = Offset(_lastViewportSize.width / 2, _lastViewportSize.height / 2);
    final translation = currentMatrix.getTranslation();
    final newTx = center.dx * (1 - factor) + translation.x * factor;
    final newTy = center.dy * (1 - factor) + translation.y * factor;

    final newMatrix = Matrix4.copy(currentMatrix)
      ..setTranslationRaw(newTx, newTy, 0.0)
      // ignore: deprecated_member_use
      ..scale(factor);

    _transformationController.value = newMatrix;
  }

  void _zoomIn() => _zoom(1.2);
  void _zoomOut() => _zoom(0.8);

  void _zoom1to1() {
    if (_decodedImage == null) return;
    final imgW = _decodedImage!.width.toDouble();
    final imgH = _decodedImage!.height.toDouble();
    final rotatedW = (_rotationAngle == 90 || _rotationAngle == 270) ? imgH : imgW;
    final rotatedH = (_rotationAngle == 90 || _rotationAngle == 270) ? imgW : imgH;

    final offsetX = (_lastViewportSize.width - rotatedW) / 2;
    final offsetY = (_lastViewportSize.height - rotatedH) / 2;

    _transformationController.value = Matrix4.translationValues(offsetX, offsetY, 0.0);
  }

  void _zoomReset() {
    if (_decodedImage == null) return;
    final imgW = _decodedImage!.width.toDouble();
    final imgH = _decodedImage!.height.toDouble();
    final rotatedW = (_rotationAngle == 90 || _rotationAngle == 270) ? imgH : imgW;
    final rotatedH = (_rotationAngle == 90 || _rotationAngle == 270) ? imgW : imgH;

    final scale = min(_lastViewportSize.width / rotatedW, _lastViewportSize.height / rotatedH);
    final renderedW = rotatedW * scale;
    final renderedH = rotatedH * scale;
    final offsetX = (_lastViewportSize.width - renderedW) / 2;
    final offsetY = (_lastViewportSize.height - renderedH) / 2;

    _transformationController.value = Matrix4.identity()
      ..setTranslationRaw(offsetX, offsetY, 0.0)
      // ignore: deprecated_member_use
      ..scale(scale);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _rootNode == null) {
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
        // 顶部精美工具栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xfff7f9fa),
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              // 刷新
              _ToolbarButton(
                icon: Icons.refresh,
                tooltip: context.l10n.t('refreshLayout'),
                onPressed: _loadLayoutAndScreenshot,
              ),
              // 保存
              _ToolbarButton(
                icon: Icons.save_outlined,
                tooltip: context.l10n.t('save'),
                onPressed: _rawScreenshotBytes != null ? _saveLayoutAndScreenshot : null,
              ),
              // 复制 XML
              _ToolbarButton(
                icon: Icons.copy_outlined,
                tooltip: context.l10n.t('copyLayout'),
                onPressed: _rootNode != null ? _copyNodeXml : null,
              ),
              const SizedBox(width: 8),
              const SizedBox(height: 20, child: VerticalDivider(width: 1, color: Colors.grey)),
              const SizedBox(width: 8),
              // 展开全部
              _ToolbarButton(
                icon: Icons.unfold_more,
                tooltip: context.l10n.t('expandAll'),
                onPressed: _rootNode != null ? _expandAllNodes : null,
              ),
              // 折叠全部
              _ToolbarButton(
                icon: Icons.unfold_less,
                tooltip: context.l10n.t('collapseAll'),
                onPressed: _rootNode != null ? _collapseAllNodes : null,
              ),
              const SizedBox(width: 12),
              // 显示属性
              _ToolbarCheckbox(
                label: context.l10n.t('showProperties'),
                value: _showProperties,
                onChanged: (val) {
                  setState(() {
                    _showProperties = val ?? true;
                  });
                },
              ),
              const SizedBox(width: 8),
              const SizedBox(height: 20, child: VerticalDivider(width: 1, color: Colors.grey)),
              const SizedBox(width: 8),
              // 旋转（左）
              _ToolbarButton(
                icon: Icons.rotate_left,
                tooltip: context.l10n.t('rotateLeft'),
                onPressed: _rootNode != null
                    ? () {
                        setState(() {
                          _rotationAngle = (_rotationAngle - 90 + 360) % 360;
                          _zoomReset();
                        });
                      }
                    : null,
              ),
              // 旋转（右）
              _ToolbarButton(
                icon: Icons.rotate_right,
                tooltip: context.l10n.t('rotateRight'),
                onPressed: _rootNode != null
                    ? () {
                        setState(() {
                          _rotationAngle = (_rotationAngle + 90) % 360;
                          _zoomReset();
                        });
                      }
                    : null,
              ),
              // 放大
              _ToolbarButton(
                icon: Icons.zoom_in,
                tooltip: context.l10n.t('zoomIn'),
                onPressed: _rootNode != null ? _zoomIn : null,
              ),
              // 缩小
              _ToolbarButton(
                icon: Icons.zoom_out,
                tooltip: context.l10n.t('zoomOut'),
                onPressed: _rootNode != null ? _zoomOut : null,
              ),
              // 1:1
              Tooltip(
                message: context.l10n.t('zoom1to1'),
                child: InkWell(
                  onTap: _rootNode != null ? _zoom1to1 : null,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[400]!),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '1:1',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // 重置
              _ToolbarButton(
                icon: Icons.settings_backup_restore,
                tooltip: context.l10n.t('zoomReset'),
                onPressed: _rootNode != null ? _zoomReset : null,
              ),
              const SizedBox(width: 12),
              // 显示边框
              _ToolbarCheckbox(
                label: context.l10n.t('showBorders'),
                value: _showBorders,
                onChanged: (val) {
                  setState(() {
                    _showBorders = val ?? false;
                  });
                },
              ),
              const Spacer(),
              // 分辨率显示
              if (_decodedImage != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    '${_decodedImage!.width}x${_decodedImage!.height}',
                    style: const TextStyle(
                      color: Colors.blueGrey,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 主内容区分裂视图
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: _showProperties ? 4 : 6,
                child: LayoutHierarchyTree(
                  rootNode: _rootNode!,
                  loading: _loading,
                  selectedNode: _selectedNode,
                  hoveredNode: _hoveredNode,
                  expandedNodes: _expandedNodes,
                  onNodeSelected: _selectNode,
                  onNodeHovered: _hoverNode,
                  onNodeExpansionChanged: (node, expanded) {
                    setState(() {
                      if (expanded) {
                        _expandedNodes.add(node);
                      } else {
                        _expandedNodes.remove(node);
                      }
                    });
                  },
                ),
              ),
              VerticalDivider(
                width: 1,
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
              // 2. 中间截图与选区
              Expanded(
                flex: _showProperties ? 4 : 6,
                child: LayoutScreenPreview(
                  rootNode: _rootNode!,
                  decodedImage: _decodedImage!,
                  selectedNode: _selectedNode,
                  hoveredNode: _hoveredNode,
                  showBorders: _showBorders,
                  rotationAngle: _rotationAngle,
                  transformationController: _transformationController,
                  onNodeSelected: _selectNode,
                  onNodeHovered: _hoverNode,
                  onViewportSizeChanged: (size) {
                    _lastViewportSize = size;
                  },
                ),
              ),
              if (_showProperties) ...[
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
            ],
          ),
        ),
      ],
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          padding: const EdgeInsets.all(6),
          minimumSize: const Size(32, 32),
        ),
      ),
    );
  }
}

class _ToolbarCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _ToolbarCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xff5f6368),
          ),
        ),
      ],
    );
  }
}
