part of '../dashboard_screen.dart';

extension _FilesTabTableHeader on _FilesTab {
  /// 文件列表表头，统一使用 Dashboard 可排序表头单元格。
  Widget _buildTableHeader(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(fileNavigationProvider);
    final notifier = ref.read(fileNavigationProvider.notifier);

    final textStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    Widget buildHeaderCell({
      required String label,
      required String column,
      double? width,
      int? flex,
      bool alignRight = false,
    }) {
      final isSorted = navState.sortColumn == column;
      return DashboardSortableHeaderCell(
        label: label,
        onTap: () => notifier.toggleSort(column),
        width: width,
        flex: flex,
        style: textStyle,
        alignRight: alignRight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        borderRadius: BorderRadius.circular(4),
        sortIcon: DashboardSortIcon(
          active: isSorted,
          ascending: navState.sortAscending,
        ),
      );
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 8, right: 16),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          buildHeaderCell(label: '名称', column: 'name', flex: 4),
          buildHeaderCell(label: '权限', column: 'permissions', width: 120),
          buildHeaderCell(label: '修改日期', column: 'date', width: 180),
          buildHeaderCell(label: '类型', column: 'type', width: 80),
          buildHeaderCell(
            label: '大小',
            column: 'size',
            width: 100,
            alignRight: true,
          ),
          const SizedBox(width: 80),
        ],
      ),
    );
  }
}
