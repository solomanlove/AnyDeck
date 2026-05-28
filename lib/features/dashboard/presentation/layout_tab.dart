import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/adb/adb_device.dart';
import '../../../core/layout_inspector/layout_inspector_service.dart';
import '../../../core/layout_inspector/layout_node.dart';
import '../../../core/providers/app_providers.dart';
import 'layout_screen_preview.dart';
import 'layout_hierarchy_tree.dart';
import 'layout_properties_table.dart';
import 'layout_toolbar.dart';

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
  final TransformationController _transformationController =
      TransformationController();
  Size _lastViewportSize = const Size(400, 800);

  @override
  void initState() {
    super.initState();
    _loadLayoutAndScreenshot();
  }

  @override
  void dispose() {
    _decodedImage?.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LayoutTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      _loadLayoutAndScreenshot(clearContent: true);
    }
  }

  Future<void> _loadLayoutAndScreenshot({bool clearContent = false}) async {
    if (_loading) return;
    final shouldClearContent = clearContent || _rootNode == null;
    setState(() {
      _loading = true;
      _error = null;
      _selectedNode = null;
      _hoveredNode = null;
      if (shouldClearContent) {
        _rootNode = null;
        _decodedImage?.dispose();
        _decodedImage = null;
        _xmlContent = null;
        _rawScreenshotBytes = null;
        _rotationAngle = 0;
        _expandedNodes.clear();
        _transformationController.value = Matrix4.identity();
      }
    });

    try {
      final snapshot = await ref
          .read(layoutInspectorServiceProvider)
          .capture(widget.device.id);
      final codec = await ui.instantiateImageCodec(snapshot.screenshotBytes);
      final frameInfo = await codec.getNextFrame();
      final decodedImg = frameInfo.image;
      codec.dispose();

      if (mounted) {
        final oldImage = _decodedImage;
        setState(() {
          _rootNode = snapshot.rootNode;
          _decodedImage = decodedImg;
          _xmlContent = snapshot.xmlContent;
          _rawScreenshotBytes = snapshot.screenshotBytes;
          _expandedNodes
            ..clear()
            ..add(snapshot.rootNode);
          _expandAll(snapshot.rootNode);
          _loading = false;
        });
        oldImage?.dispose();
      } else {
        decodedImg.dispose();
      }
    } on LayoutInspectorException catch (e) {
      final result = e.result;
      if (result != null) {
        await ref
            .read(deviceRegistryProvider.notifier)
            .syncAfterAdbResult(result);
      }
      if (mounted) {
        setState(() {
          _error = e.message;
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
    if (_selectedNode == node) return;
    setState(() {
      _selectedNode = node;
      if (node != null) {
        _expandAncestors(node);
      }
    });
  }

  void _hoverNode(LayoutNode? node) {
    if (_hoveredNode == node) return;
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
      _expandedNodes.clear();
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
        suggestedName:
            'layout_${widget.device.id}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      if (location == null) return;

      final basePath = location.path;
      final pngFile = File(basePath);
      await pngFile.writeAsBytes(_rawScreenshotBytes!);

      final xmlPath =
          '${basePath.replaceAll(RegExp(r'\.png$', caseSensitive: false), '')}.xml';
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

    final center = Offset(
      _lastViewportSize.width / 2,
      _lastViewportSize.height / 2,
    );
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
    final rotatedW = (_rotationAngle == 90 || _rotationAngle == 270)
        ? imgH
        : imgW;
    final rotatedH = (_rotationAngle == 90 || _rotationAngle == 270)
        ? imgW
        : imgH;

    final offsetX = (_lastViewportSize.width - rotatedW) / 2;
    final offsetY = (_lastViewportSize.height - rotatedH) / 2;

    _transformationController.value = Matrix4.translationValues(
      offsetX,
      offsetY,
      0.0,
    );
  }

  void _zoomReset() {
    if (_decodedImage == null) return;
    final imgW = _decodedImage!.width.toDouble();
    final imgH = _decodedImage!.height.toDouble();
    final rotatedW = (_rotationAngle == 90 || _rotationAngle == 270)
        ? imgH
        : imgW;
    final rotatedH = (_rotationAngle == 90 || _rotationAngle == 270)
        ? imgW
        : imgH;

    final scale = min(
      _lastViewportSize.width / rotatedW,
      _lastViewportSize.height / rotatedH,
    );
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
        LayoutToolbar(
          hasLayout: _rootNode != null,
          canSave: _rawScreenshotBytes != null,
          showProperties: _showProperties,
          showBorders: _showBorders,
          resolutionText: _decodedImage == null
              ? null
              : '${_decodedImage!.width}x${_decodedImage!.height}',
          onRefresh: _loadLayoutAndScreenshot,
          onSave: _saveLayoutAndScreenshot,
          onCopyXml: _copyNodeXml,
          onExpandAll: _expandAllNodes,
          onCollapseAll: _collapseAllNodes,
          onShowPropertiesChanged: (val) {
            setState(() {
              _showProperties = val ?? true;
            });
          },
          onRotateLeft: () {
            setState(() {
              _rotationAngle = (_rotationAngle - 90 + 360) % 360;
              _zoomReset();
            });
          },
          onRotateRight: () {
            setState(() {
              _rotationAngle = (_rotationAngle + 90) % 360;
              _zoomReset();
            });
          },
          onZoomIn: _zoomIn,
          onZoomOut: _zoomOut,
          onZoom1To1: _zoom1to1,
          onZoomReset: _zoomReset,
          onShowBordersChanged: (val) {
            setState(() {
              _showBorders = val ?? false;
            });
          },
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
                  child: LayoutPropertiesTable(selectedNode: _selectedNode),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
