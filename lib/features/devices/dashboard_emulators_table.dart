part of '../dashboard_screen.dart';

/// 模拟器数据表格组件，负责展示模拟器列表及其列排序、滚动等逻辑。
class _EmulatorTable extends StatefulWidget {
  const _EmulatorTable({
    required this.items,
    required this.selectedName,
    required this.onSort,
    required this.sortIconBuilder,
    required this.onSelected,
    required this.onDoubleTap,
  });

  /// 模拟器数据列表项
  final List<_EmulatorItem> items;

  /// 当前选中模拟器的名称
  final String? selectedName;

  /// 点击表头排序的回调
  final ValueChanged<String> onSort;

  /// 根据排序列生成排序图标的回调
  final Widget Function(String column) sortIconBuilder;

  /// 单击选中行的回调
  final ValueChanged<String> onSelected;

  /// 双击行的回调 (例如双击查看详情)
  final ValueChanged<String> onDoubleTap;

  @override
  State<_EmulatorTable> createState() => _EmulatorTableState();
}

class _EmulatorTableState extends State<_EmulatorTable> {
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _EmulatorTableHeader(
          onSort: widget.onSort,
          sortIconBuilder: widget.sortIconBuilder,
        ),
        Expanded(
          child: Scrollbar(
            controller: _verticalController,
            child: ListView.builder(
              controller: _verticalController,
              primary: false,
              itemCount: widget.items.length,
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return _EmulatorTableRow(
                  item: item,
                  selected: item.emulator.name == widget.selectedName,
                  index: index,
                  onSelected: () => widget.onSelected(item.emulator.name),
                  onDoubleTap: () => widget.onDoubleTap(item.emulator.name),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// 表头与数据行共用列宽权重和边距，名称列为状态和详情按钮预留空间。
abstract final class _EmulatorTableLayout {
  static const name = 30;
  static const resolution = 18;
  static const sdk = 14;
  static const abi = 16;
  static const memory = 11;
  static const storage = 11;
  static const cellPadding = EdgeInsets.symmetric(horizontal: 6);

  // 与单元格边距合计 28，首尾内容对齐工具栏两侧。
  static const pagePadding = EdgeInsets.symmetric(horizontal: 22, vertical: 12);
}

/// 模拟器数据表格的头部组件。
class _EmulatorTableHeader extends StatelessWidget {
  const _EmulatorTableHeader({
    required this.onSort,
    required this.sortIconBuilder,
  });

  /// 排序回调
  final ValueChanged<String> onSort;

  /// 排序图标生成器
  final Widget Function(String column) sortIconBuilder;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      // 分隔线覆盖在内容上，避免底部边框将表头内容向上挤。
      foregroundDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 模拟器名称表头单元格
          DashboardSortableHeaderCell(
            flex: _EmulatorTableLayout.name,
            label: context.l10n.t('emulatorNameCol'),
            style: style,
            onTap: () => onSort('name'),
            padding: _EmulatorTableLayout.cellPadding,
            sortIcon: sortIconBuilder('name'),
          ),
          // 分辨率表头单元格
          DashboardSortableHeaderCell(
            flex: _EmulatorTableLayout.resolution,
            label: context.l10n.t('emulatorResolutionCol'),
            style: style,
            onTap: () => onSort('resolution'),
            padding: _EmulatorTableLayout.cellPadding,
            sortIcon: sortIconBuilder('resolution'),
          ),
          // SDK表头单元格
          DashboardSortableHeaderCell(
            flex: _EmulatorTableLayout.sdk,
            label: context.l10n.t('emulatorSdkCol'),
            style: style,
            onTap: () => onSort('sdk'),
            padding: _EmulatorTableLayout.cellPadding,
            sortIcon: sortIconBuilder('sdk'),
          ),
          // ABI架构表头单元格
          DashboardSortableHeaderCell(
            flex: _EmulatorTableLayout.abi,
            label: context.l10n.t('emulatorAbiCol'),
            style: style,
            onTap: () => onSort('abi'),
            padding: _EmulatorTableLayout.cellPadding,
            sortIcon: sortIconBuilder('abi'),
          ),
          // 内存容量表头单元格
          DashboardSortableHeaderCell(
            flex: _EmulatorTableLayout.memory,
            label: context.l10n.t('emulatorMemoryCol'),
            style: style,
            onTap: () => onSort('memory'),
            padding: _EmulatorTableLayout.cellPadding,
            sortIcon: sortIconBuilder('memory'),
          ),
          // 存储容量表头单元格
          DashboardSortableHeaderCell(
            flex: _EmulatorTableLayout.storage,
            label: context.l10n.t('emulatorStorageCol'),
            style: style,
            onTap: () => onSort('storage'),
            alignRight: true,
            padding: _EmulatorTableLayout.cellPadding,
            sortIcon: sortIconBuilder('storage'),
          ),
        ],
      ),
    );
  }
}

/// 模拟器数据行组件。
class _EmulatorTableRow extends StatelessWidget {
  const _EmulatorTableRow({
    required this.item,
    required this.selected,
    required this.index,
    required this.onSelected,
    required this.onDoubleTap,
  });

  /// 模拟器项数据
  final _EmulatorItem item;

  /// 是否被选中
  final bool selected;

  /// 行的索引，用于交替背景色
  final int index;

  /// 单击选中行回调
  final VoidCallback onSelected;

  /// 双击行回调
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    // 选中时使用高亮色，未选中时奇偶行背景交替
    final Color? rowColor = selected
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
        : index % 2 == 0
        ? null
        : Theme.of(
            context,
          ).colorScheme.surfaceContainerLowest.withValues(alpha: 0.5);

    return InkWell(
      onTap: onSelected,
      onDoubleTap: onDoubleTap,
      child: Container(
        height: (item.status == 'error' || item.status == 'connectionIssue') ? 88 : 56,
        decoration: BoxDecoration(color: rowColor),
        foregroundDecoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // 名称列包含状态圆点与名称
            _EmulatorCell(
              flex: _EmulatorTableLayout.name,
              child: Row(
                children: [
                  if ((item.status == 'error' || item.status == 'connectionIssue'))
                    _EmulatorErrorButton(launch: item.launch!)
                  else
                    _EmulatorStatusDot(status: item.status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _EmulatorTableText(item.emulator.displayName),
                        if ((item.status == 'error' || item.status == 'connectionIssue'))
                          Tooltip(
                            message: _emulatorErrorText(context, item.launch!),
                            child: Text(
                              _emulatorErrorSummary(context, item.launch!),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: item.status == 'connectionIssue'
                                    ? Theme.of(context).colorScheme.tertiary
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.t('emulatorViewDetails'),
                    icon: const Icon(CupertinoIcons.info_circle, size: 18),
                    onPressed: onDoubleTap,
                  ),
                ],
              ),
            ),
            // 分辨率列
            _EmulatorCell(
              flex: _EmulatorTableLayout.resolution,
              child: _EmulatorTableText(item.emulator.resolutionLabel),
            ),
            // SDK 版本列
            _EmulatorCell(
              flex: _EmulatorTableLayout.sdk,
              child: _EmulatorTableText(item.emulator.sdkVersionLabel),
            ),
            // ABI架构列
            _EmulatorCell(
              flex: _EmulatorTableLayout.abi,
              child: _EmulatorTableText(item.emulator.abiLabel),
            ),
            // 内存列
            _EmulatorCell(
              flex: _EmulatorTableLayout.memory,
              child: _EmulatorTableText(item.emulator.memoryLabel),
            ),
            // 存储列
            _EmulatorCell(
              flex: _EmulatorTableLayout.storage,
              alignment: Alignment.centerRight,
              child: _EmulatorTableText(item.emulator.storageLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// 按列宽权重分配可用空间，并与表头使用相同的水平边距。
class _EmulatorCell extends StatelessWidget {
  const _EmulatorCell({
    required this.flex,
    required this.child,
    this.alignment = Alignment.centerLeft,
  });

  final int flex;
  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: _EmulatorTableLayout.cellPadding,
        alignment: alignment,
        child: child,
      ),
    );
  }
}

/// 用于表格中单行文本显示的组件，自带悬浮 tooltip 提示。
class _EmulatorTableText extends StatelessWidget {
  const _EmulatorTableText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: value,
      waitDuration: const Duration(milliseconds: 600),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

/// 模拟器运行状态状态指示圆点。
class _EmulatorStatusDot extends StatelessWidget {
  const _EmulatorStatusDot({required this.status});

  /// 模拟器状态字符串 ('running', 'starting', 'stopped'等)
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'running' => (Theme.of(context).colorScheme.primary, context.l10n.t('emulatorRunning')),
      'starting' => (
        const Color(0xFFE65100),
        context.l10n.t('emulatorStarting'),
      ),
      _ => (const Color(0xFF9E9E9E), context.l10n.t('emulatorStopped')),
    };

    return Tooltip(
      message: label,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
