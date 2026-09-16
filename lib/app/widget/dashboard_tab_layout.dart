import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// 统一的仪表盘顶部搜索及工具栏组件。
/// 
/// 泛型 [T] 用于指定分段选择器（Segmented Control）的值类型（通常是一个 enum）。
/// 
/// 该组件主要包含以下三部分：
/// 1. 左侧：具有搜索功能的输入框 [TextField]
/// 2. 中间：分类筛选的分段选择器 [CupertinoSlidingSegmentedControl]
/// 3. 右侧：自定义的附加操作按钮（如刷新、视图切换等）的扩展插槽 [trailingActions]
/// 
/// 实现了 UI 和数据的分离，本身不管理状态，所有的状态及回调都需要由父 Widget 传入。
class DashboardSearchToolbar<T extends Object> extends StatelessWidget {
  const DashboardSearchToolbar({
    super.key,
    required this.searchController,
    required this.searchHint,
    this.searchFocusNode,
    this.searchKey,
    this.searchTapRegionGroupId,
    required this.onSearchChanged,
    this.onSearchSubmitted,
    required this.onSearchClear,
    required this.hasSearchQuery,
    required this.segments,
    required this.currentSegment,
    required this.onSegmentChanged,
    required this.trailingActions,
  });

  /// 搜索框的文本控制器，用于管理当前输入的文本。
  final TextEditingController searchController;

  /// 搜索框为空时的占位提示文本。
  final String searchHint;

  /// 搜索框的焦点节点。如果在外部需要监听其焦点变化，可传入该参数。
  final FocusNode? searchFocusNode;

  /// 搜索框的 GlobalKey。通常在需要获取输入框在屏幕上的渲染位置（如显示 Overlay 菜单）时使用。
  final Key? searchKey;

  /// 如果传入该值，则会对搜索框包裹一个 [TapRegion]。
  /// 这主要用于在搜索框外部点击时收起输入法或关闭特定的 Overlay。
  final String? searchTapRegionGroupId;

  /// 搜索内容改变时的回调，用于触发过滤逻辑更新。
  final ValueChanged<String> onSearchChanged;

  /// 搜索框提交（按回车）时的回调，通常用于记录搜索历史。
  final ValueChanged<String>? onSearchSubmitted;

  /// 点击搜索框右侧 "清除" 图标时的回调，用于清空内容。
  final VoidCallback onSearchClear;

  /// 标识当前是否有搜索内容（用来控制清除图标的显示与隐藏）。
  final bool hasSearchQuery;

  /// 分段选择器（Segmented Control）的选项，键值对形如: `枚举值: 组件(Text)`。
  final Map<T, Widget> segments;

  /// 当前选中的分段。
  final T currentSegment;

  /// 分段选项切换时的回调。
  final ValueChanged<T?> onSegmentChanged;

  /// 工具栏右侧额外的操作按钮列表。
  /// 例如：刷新按钮、Checkbox、"列表/网格"切换视图按钮等。
  final List<Widget> trailingActions;

  /// 内部封装构建 TextField 组件
  Widget _buildTextField(BuildContext context) {
    return TextField(
      key: searchKey,
      focusNode: searchFocusNode,
      controller: searchController,
      decoration: InputDecoration(
        prefixIcon: const Icon(
          CupertinoIcons.line_horizontal_3_decrease,
          size: 16,
        ),
        hintText: searchHint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        suffixIcon: hasSearchQuery
            ? IconButton(
                icon: const Icon(CupertinoIcons.clear, size: 16),
                onPressed: onSearchClear,
              )
            : null,
      ),
      onChanged: onSearchChanged,
      onSubmitted: onSearchSubmitted,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 1. 左侧：输入框（撑满剩余空间）
        Expanded(
          child: SizedBox(
            height: 38,
            child: searchTapRegionGroupId != null
                ? TapRegion(
                    groupId: searchTapRegionGroupId,
                    child: _buildTextField(context),
                  )
                : _buildTextField(context),
          ),
        ),
        const SizedBox(width: 12),
        // 2. 中间：类别分段选择器
        CupertinoSlidingSegmentedControl<T>(
          groupValue: currentSegment,
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
              : const Color(0xFFF1F5F9),
          thumbColor: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).colorScheme.surfaceContainerHigh
              : Colors.white,
          padding: const EdgeInsets.all(3),
          children: segments,
          onValueChanged: onSegmentChanged,
        ),
        const SizedBox(width: 8),
        // 3. 右侧：补充额外操作区
        ...trailingActions,
      ],
    );
  }
}

/// 仪表盘下各 Tab 页的统一基础布局结构。
/// 
/// 包含了统一的边距（Padding），并采用垂直线性排布（Column），
/// 将页面分为顶部的 [toolbar] 和下方占满剩余空间的 [body]。
class DashboardTabLayout extends StatelessWidget {
  const DashboardTabLayout({
    super.key,
    required this.toolbar,
    required this.body,
  });

  /// 顶部的工具栏，通常传入 [DashboardSearchToolbar]。
  final Widget toolbar;

  /// 下方的核心内容展示区（如列表、网格、表格等），会被包裹在 Expanded 中。
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          toolbar,
          const SizedBox(height: 12),
          Expanded(child: body),
        ],
      ),
    );
  }
}
