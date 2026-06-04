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
  // 横向和纵向滚动控制器
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 自适应计算各列的宽度
        final widths = _EmulatorTableWidths.adaptive(constraints.maxWidth);
        // 如果各列总宽度小于容器宽度，则拉伸至容器宽度
        final tableWidth = max(widths.total, constraints.maxWidth);

        return Scrollbar(
          controller: _horizontalController,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontalController,
            primary: false,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  // 表格头部
                  _EmulatorTableHeader(
                    widths: widths,
                    onSort: widget.onSort,
                    sortIconBuilder: widget.sortIconBuilder,
                  ),
                  // 表格内容列表
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
                            widths: widths,
                            selected: item.emulator.name == widget.selectedName,
                            index: index,
                            onSelected: () =>
                                widget.onSelected(item.emulator.name),
                            onDoubleTap: () =>
                                widget.onDoubleTap(item.emulator.name),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 模拟器数据表格中各列的宽度定义。
class _EmulatorTableWidths {
  const _EmulatorTableWidths({
    required this.name,
    required this.resolution,
    required this.sdk,
    required this.abi,
    required this.memory,
    required this.storage,
  });

  /// 模拟器名称列宽
  final double name;
  /// 分辨率列宽
  final double resolution;
  /// SDK 版本列宽
  final double sdk;
  /// ABI 架构列宽
  final double abi;
  /// 内存列宽
  final double memory;
  /// 存储空间列宽
  final double storage;

  /// 各列宽度总和
  double get total => name + resolution + sdk + abi + memory + storage;

  /// 工厂构造方法：根据当前可视区域宽度动态计算名称列的宽度，保持其他列宽度固定。
  factory _EmulatorTableWidths.adaptive(double viewportWidth) {
    const fixed = 180.0 + 130.0 + 210.0 + 110.0 + 110.0;
    final name = max(280.0, viewportWidth - fixed);
    return _EmulatorTableWidths(
      name: name,
      resolution: 180,
      sdk: 130,
      abi: 210,
      memory: 110,
      storage: 110,
    );
  }
}

/// 模拟器数据表格的头部组件。
class _EmulatorTableHeader extends StatelessWidget {
  const _EmulatorTableHeader({
    required this.widths,
    required this.onSort,
    required this.sortIconBuilder,
  });

  /// 列宽定义
  final _EmulatorTableWidths widths;
  /// 排序回调
  final ValueChanged<String> onSort;
  /// 排序图标生成器
  final Widget Function(String column) sortIconBuilder;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .titleSmall
        ?.copyWith(fontWeight: FontWeight.bold);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          // 模拟器名称表头单元格
          _EmulatorHeaderCell(
            width: widths.name,
            label: context.l10n.t('emulatorNameCol'),
            style: style,
            onTap: () => onSort('name'),
            sortIcon: sortIconBuilder('name'),
          ),
          // 分辨率表头单元格
          _EmulatorHeaderCell(
            width: widths.resolution,
            label: context.l10n.t('emulatorResolutionCol'),
            style: style,
            onTap: () => onSort('resolution'),
            sortIcon: sortIconBuilder('resolution'),
          ),
          // SDK表头单元格
          _EmulatorHeaderCell(
            width: widths.sdk,
            label: context.l10n.t('emulatorSdkCol'),
            style: style,
            onTap: () => onSort('sdk'),
            sortIcon: sortIconBuilder('sdk'),
          ),
          // ABI架构表头单元格
          _EmulatorHeaderCell(
            width: widths.abi,
            label: context.l10n.t('emulatorAbiCol'),
            style: style,
            onTap: () => onSort('abi'),
            sortIcon: sortIconBuilder('abi'),
          ),
          // 内存容量表头单元格
          _EmulatorHeaderCell(
            width: widths.memory,
            label: context.l10n.t('emulatorMemoryCol'),
            style: style,
            onTap: () => onSort('memory'),
            sortIcon: sortIconBuilder('memory'),
          ),
          // 存储容量表头单元格
          _EmulatorHeaderCell(
            width: widths.storage,
            label: context.l10n.t('emulatorStorageCol'),
            style: style,
            onTap: () => onSort('storage'),
            sortIcon: sortIconBuilder('storage'),
          ),
        ],
      ),
    );
  }
}

/// 表头单个单元格组件，支持点击排序。
class _EmulatorHeaderCell extends StatelessWidget {
  const _EmulatorHeaderCell({
    required this.width,
    required this.label,
    required this.style,
    required this.onTap,
    required this.sortIcon,
  });

  /// 宽度
  final double width;
  /// 表头标签文本
  final String label;
  /// 文本样式
  final TextStyle? style;
  /// 点击回调
  final VoidCallback onTap;
  /// 排序状态图标
  final Widget sortIcon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              sortIcon,
            ],
          ),
        ),
      ),
    );
  }
}

/// 模拟器数据行组件。
class _EmulatorTableRow extends StatelessWidget {
  const _EmulatorTableRow({
    required this.item,
    required this.widths,
    required this.selected,
    required this.index,
    required this.onSelected,
    required this.onDoubleTap,
  });

  /// 模拟器项数据
  final _EmulatorItem item;
  /// 列宽定义
  final _EmulatorTableWidths widths;
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
    final color = selected
        ? Theme.of(context).colorScheme.primaryContainer
        : index.isOdd
            ? Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.45)
            : null;

    return InkWell(
      onTap: onSelected,
      onDoubleTap: onDoubleTap,
      child: Container(
        height: 40,
        color: color,
        child: Row(
          children: [
            // 名称列包含状态圆点与名称
            _EmulatorCell(
              width: widths.name,
              child: Row(
                children: [
                  _EmulatorStatusDot(status: item.status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _EmulatorTableText(item.emulator.displayName),
                  ),
                ],
              ),
            ),
            // 分辨率列
            _EmulatorCell(
              width: widths.resolution,
              child: _EmulatorTableText(item.emulator.resolutionLabel),
            ),
            // SDK 版本列
            _EmulatorCell(
              width: widths.sdk,
              child: _EmulatorTableText(item.emulator.sdkVersionLabel),
            ),
            // ABI架构列
            _EmulatorCell(
              width: widths.abi,
              child: _EmulatorTableText(item.emulator.abiLabel),
            ),
            // 内存列
            _EmulatorCell(
              width: widths.memory,
              child: _EmulatorTableText(item.emulator.memoryLabel),
            ),
            // 存储列
            _EmulatorCell(
              width: widths.storage,
              child: _EmulatorTableText(item.emulator.storageLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// 表格内部的基础单元格容器，限制宽度并提供水平边距。
class _EmulatorCell extends StatelessWidget {
  const _EmulatorCell({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
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
      child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
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
      'running' => (
          const Color(0xFF2E7D32),
          context.l10n.t('emulatorRunning'),
        ),
      'starting' => (
          const Color(0xFFE65100),
          context.l10n.t('emulatorStarting'),
        ),
      _ => (
          const Color(0xFF9E9E9E),
          context.l10n.t('emulatorStopped'),
        ),
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
