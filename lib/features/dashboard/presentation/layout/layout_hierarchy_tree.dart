import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../../../app/l10n/app_localizations.dart';
import '../../../../core/layout_inspector/layout_node.dart';

/// 渲染左侧树状 XML 节点结构，支持由父组件驱动的展开、折叠、高亮与悬停。
class LayoutHierarchyTree extends StatefulWidget {
  final LayoutNode rootNode;
  final bool loading;
  final LayoutNode? selectedNode;
  final LayoutNode? hoveredNode;
  final Set<LayoutNode> expandedNodes;
  final ValueChanged<LayoutNode?> onNodeSelected;
  final ValueChanged<LayoutNode?> onNodeHovered;
  final void Function(LayoutNode node, bool expanded) onNodeExpansionChanged;

  const LayoutHierarchyTree({
    super.key,
    required this.rootNode,
    this.loading = false,
    required this.selectedNode,
    this.hoveredNode,
    required this.expandedNodes,
    required this.onNodeSelected,
    required this.onNodeHovered,
    required this.onNodeExpansionChanged,
  });

  @override
  State<LayoutHierarchyTree> createState() => _LayoutHierarchyTreeState();
}

class _LayoutHierarchyTreeState extends State<LayoutHierarchyTree> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                const Icon(
                  CupertinoIcons.square_stack_3d_up,
                  size: 18,
                  color: Colors.blueGrey,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.t('nodeHierarchy'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.blueGrey,
                  ),
                ),
              ],
            ),
          ),
          // 树结构展示区
          Expanded(
            child: Stack(
              children: [
                Opacity(
                  opacity: widget.loading ? 0.4 : 1.0,
                  child: IgnorePointer(
                    ignoring: widget.loading,
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        scrollDirection: Axis.vertical,
                        padding: const EdgeInsets.all(8),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 600),
                            child: _TreeNodeWidget(
                              node: widget.rootNode,
                              depth: 0,
                              selectedNode: widget.selectedNode,
                              hoveredNode: widget.hoveredNode,
                              expandedNodes: widget.expandedNodes,
                              onNodeSelected: widget.onNodeSelected,
                              onNodeHovered: widget.onNodeHovered,
                              onNodeExpansionChanged:
                                  widget.onNodeExpansionChanged,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.loading)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TreeNodeWidget extends StatefulWidget {
  final LayoutNode node;
  final int depth;
  final LayoutNode? selectedNode;
  final LayoutNode? hoveredNode;
  final Set<LayoutNode> expandedNodes;
  final ValueChanged<LayoutNode?> onNodeSelected;
  final ValueChanged<LayoutNode?> onNodeHovered;
  final void Function(LayoutNode node, bool expanded) onNodeExpansionChanged;

  const _TreeNodeWidget({
    required this.node,
    required this.depth,
    required this.selectedNode,
    required this.hoveredNode,
    required this.expandedNodes,
    required this.onNodeSelected,
    required this.onNodeHovered,
    required this.onNodeExpansionChanged,
  });

  @override
  State<_TreeNodeWidget> createState() => _TreeNodeWidgetState();
}

class _TreeNodeWidgetState extends State<_TreeNodeWidget> {
  @override
  void initState() {
    super.initState();
    _scrollToMeIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _TreeNodeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedNode == widget.node &&
        oldWidget.selectedNode != widget.node) {
      _scrollToMeIfNeeded();
    }
  }

  void _scrollToMeIfNeeded() {
    if (widget.selectedNode == widget.node) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // 查找外层 Axis.vertical 方向的垂直滚动组件，避免被内层水平滚动组件拦截
          ScrollableState? verticalScrollable;
          ScrollableState? currentScrollable = context
              .findAncestorStateOfType<ScrollableState>();
          while (currentScrollable != null) {
            if (currentScrollable.widget.axis == Axis.vertical) {
              verticalScrollable = currentScrollable;
              break;
            }
            currentScrollable = currentScrollable.context
                .findAncestorStateOfType<ScrollableState>();
          }

          if (verticalScrollable != null) {
            final renderObject = context.findRenderObject();
            if (renderObject == null || !renderObject.attached) {
              return;
            }
            verticalScrollable.position.ensureVisible(
              renderObject,
              alignment: 0.3, // 滚动到视口偏上 30% 位置以获得最佳视觉效果
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
            );
          }
        }
      });
    }
  }

  Widget _buildSyntaxHighlightedNode(LayoutNode node) {
    final spans = <TextSpan>[];
    spans.add(
      const TextSpan(
        text: '<',
        style: TextStyle(color: Colors.grey),
      ),
    );
    spans.add(
      TextSpan(
        text: node.className.split('.').last,
        style: const TextStyle(
          color: Color(0xff881280),
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    void addAttr(String key, String value) {
      if (value.isEmpty) return;
      spans.add(const TextSpan(text: ' '));
      spans.add(
        TextSpan(
          text: key,
          style: const TextStyle(color: Color(0xff994500)),
        ),
      );
      spans.add(
        const TextSpan(
          text: '="',
          style: TextStyle(color: Colors.grey),
        ),
      );
      spans.add(
        TextSpan(
          text: value,
          style: const TextStyle(color: Color(0xff1a1aa6)),
        ),
      );
      spans.add(
        const TextSpan(
          text: '"',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    addAttr('index', node.index.toString());
    if (node.resourceId.isNotEmpty) {
      final idPart = node.resourceId.contains('/')
          ? node.resourceId.split('/').last
          : node.resourceId;
      addAttr('resource-id', idPart);
    }
    if (node.text.isNotEmpty) {
      addAttr(
        'text',
        node.text.length > 25 ? '${node.text.substring(0, 25)}...' : node.text,
      );
    }
    if (node.contentDesc.isNotEmpty) {
      addAttr(
        'content-desc',
        node.contentDesc.length > 25
            ? '${node.contentDesc.substring(0, 25)}...'
            : node.contentDesc,
      );
    }
    addAttr('bounds', node.bounds);

    spans.add(
      TextSpan(
        text: node.children.isEmpty ? ' />' : '>',
        style: const TextStyle(color: Colors.grey),
      ),
    );

    return RichText(
      text: TextSpan(
        children: spans,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.selectedNode == widget.node;
    final isHovered = widget.hoveredNode == widget.node;
    final isExpanded = widget.expandedNodes.contains(widget.node);

    final List<Widget> treeChildren = [];
    if (isExpanded && widget.node.children.isNotEmpty) {
      for (final child in widget.node.children) {
        treeChildren.add(
          _TreeNodeWidget(
            node: child,
            depth: widget.depth + 1,
            selectedNode: widget.selectedNode,
            hoveredNode: widget.hoveredNode,
            expandedNodes: widget.expandedNodes,
            onNodeSelected: widget.onNodeSelected,
            onNodeHovered: widget.onNodeHovered,
            onNodeExpansionChanged: widget.onNodeExpansionChanged,
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 节点单行元素
        MouseRegion(
          onEnter: (_) => widget.onNodeHovered(widget.node),
          onExit: (_) => widget.onNodeHovered(null),
          child: GestureDetector(
            onTap: () => widget.onNodeSelected(widget.node),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xff09c47c).withValues(alpha: 0.18)
                    : isHovered
                    ? Colors.grey.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 缩进占位
                  SizedBox(width: widget.depth * 16.0),
                  // 展开/收起小箭头
                  if (widget.node.children.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        widget.onNodeExpansionChanged(widget.node, !isExpanded);
                      },
                      child: Icon(
                        isExpanded
                            ? CupertinoIcons.chevron_down
                            : CupertinoIcons.chevron_right,
                        size: 16,
                        color: Colors.grey[700],
                      ),
                    )
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 4),
                  // 节点 XML 结构
                  _buildSyntaxHighlightedNode(widget.node),
                ],
              ),
            ),
          ),
        ),
        // 子节点递归
        if (isExpanded && treeChildren.isNotEmpty) ...treeChildren,
        // 如果有子节点且已展开，绘制闭合标签
        if (isExpanded && widget.node.children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: (widget.depth * 16.0) + 20), // 缩进配合
                RichText(
                  text: TextSpan(
                    children: [
                      const TextSpan(
                        text: '</',
                        style: TextStyle(color: Colors.grey),
                      ),
                      TextSpan(
                        text: widget.node.className.split('.').last,
                        style: const TextStyle(
                          color: Color(0xff881280),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const TextSpan(
                        text: '>',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
