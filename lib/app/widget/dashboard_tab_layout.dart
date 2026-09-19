import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'dashboard_history_text_field.dart';

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
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onSearchClear,
    required this.hasSearchQuery,
    required this.searchHistory,
    required this.onSearchHistorySelected,
    required this.onSearchHistoryRemoved,
    this.searchDefaultOptions = const [],
    this.onSearchHistoryCleared,
    required this.segments,
    required this.currentSegment,
    required this.onSegmentChanged,
    required this.trailingActions,
  });

  /// 搜索框的文本控制器，用于管理当前输入的文本。
  final TextEditingController searchController;

  /// 搜索框为空时的占位提示文本。
  final String searchHint;

  /// 搜索内容改变时的回调，用于触发过滤逻辑更新。
  final ValueChanged<String> onSearchChanged;

  /// 搜索框提交（按回车）时的回调，通常用于记录搜索历史。
  final ValueChanged<String> onSearchSubmitted;

  /// 点击搜索框右侧 "清除" 图标时的回调，用于清空内容。
  final VoidCallback onSearchClear;

  /// 标识当前是否有搜索内容（用来控制清除图标的显示与隐藏）。
  final bool hasSearchQuery;

  /// 已提交的搜索历史，仅在当前 Tab 中展示。
  final List<String> searchHistory;

  /// 选中或删除历史记录时的回调。
  final ValueChanged<String> onSearchHistorySelected;
  final ValueChanged<String> onSearchHistoryRemoved;

  /// 固定快捷项和可选的清空历史操作。
  final List<DashboardHistoryOption> searchDefaultOptions;
  final VoidCallback? onSearchHistoryCleared;

  /// 分段选择器（Segmented Control）的选项，键值对形如: `枚举值: 组件(Text)`。
  final Map<T, Widget> segments;

  /// 当前选中的分段。
  final T currentSegment;

  /// 分段选项切换时的回调。
  final ValueChanged<T?> onSegmentChanged;

  /// 工具栏右侧额外的操作按钮列表。
  /// 例如：刷新按钮、Checkbox、"列表/网格"切换视图按钮等。
  final List<Widget> trailingActions;

  /// 内部封装带历史下拉的筛选输入框。
  Widget _buildTextField(BuildContext context) {
    return DashboardHistoryTextField(
      controller: searchController,
      hintText: searchHint,
      history: searchHistory,
      defaultOptions: searchDefaultOptions,
      onChanged: onSearchChanged,
      onSubmitted: onSearchSubmitted,
      onSelected: onSearchHistorySelected,
      onHistoryRemoved: onSearchHistoryRemoved,
      onHistoryCleared: onSearchHistoryCleared,
      onClear: onSearchClear,
      hasQuery: hasSearchQuery,
      textStyle: Theme.of(context).textTheme.bodyMedium,
    );
  }

  /// 内部封装分类筛选的分段选择器。
  Widget _buildSegmentedControl(BuildContext context) {
    return CupertinoSlidingSegmentedControl<T>(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 当可用宽度较窄（小于 760）时，为了避免输入框被过度挤压或右侧操作按钮溢出，
        // 采用双行自适应布局：上行展开搜索框，下行放置分段筛选与操作区。
        final isNarrow = constraints.maxWidth < 760;
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 38,
                child: _buildTextField(context),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  _buildSegmentedControl(context),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: trailingActions,
                  ),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            // 1. 左侧：输入框（撑满剩余空间）
            Expanded(
              child: SizedBox(
                height: 38,
                child: _buildTextField(context),
              ),
            ),
            const SizedBox(width: 12),
            // 2. 中间：类别分段选择器
            _buildSegmentedControl(context),
            const SizedBox(width: 8),
            // 3. 右侧：补充额外操作区
            ...trailingActions,
          ],
        );
      },
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
