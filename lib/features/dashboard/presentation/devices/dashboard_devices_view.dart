part of '../dashboard_screen.dart';

/// 设备列表主体布局：负责排序、空态、表头和 Card 容器。
extension _DeviceListPanelView on _DeviceListPanelState {
  Widget _buildDeviceListPanel(BuildContext context) {
    final activeDevicesAsync = ref.watch(devicesProvider);
    final items = ref.watch(deviceRegistryProvider);
    final sortedItems = _sortedDevices(items);
    final selectedCount = items.where((device) => device.isChecked).length;
    final allChecked = items.isNotEmpty && selectedCount == items.length;
    final hasChecked = selectedCount > 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        final hasBoundedHeight = constraints.hasBoundedHeight;
        final contentWidget = _buildDeviceListContent(
          context: context,
          activeDevicesAsync: activeDevicesAsync,
          sortedItems: sortedItems,
          isCompact: isCompact,
          hasBoundedHeight: hasBoundedHeight,
        );

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        Widget panelCard = ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.04),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (sortedItems.isNotEmpty) ...[
                    _buildTableHeader(context, isCompact, allChecked, hasChecked),
                    const SizedBox(height: 4),
                  ],
                  if (hasBoundedHeight)
                    Expanded(child: contentWidget)
                  else
                    contentWidget,
                ],
              ),
            ),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasChecked) ...[
              _buildBatchActionsToolbar(
                context,
                items.where((d) => d.isChecked).toList(),
              ),
              const SizedBox(height: 16),
            ],
            if (hasBoundedHeight)
              Expanded(child: panelCard)
            else
              panelCard,
          ],
        );
      },
    );
  }

  List<RegisteredDevice> _sortedDevices(List<RegisteredDevice> items) {
    final sortedItems = List<RegisteredDevice>.from(items);
    sortedItems.sort((a, b) {
      // 在线设备始终置顶，避免离线历史记录打断当前调试流程。
      if (a.isOnline && !b.isOnline) return -1;
      if (!a.isOnline && b.isOnline) return 1;

      final cmp = switch (_sortColumn) {
        'name' => a.displayName.compareTo(b.displayName),
        'status' => a.status.compareTo(b.status),
        _ => a.id.compareTo(b.id),
      };
      return _sortAscending ? cmp : -cmp;
    });
    return sortedItems;
  }

  Widget _buildDeviceListContent({
    required BuildContext context,
    required AsyncValue<List<AdbDevice>> activeDevicesAsync,
    required List<RegisteredDevice> sortedItems,
    required bool isCompact,
    required bool hasBoundedHeight,
  }) {
    if (activeDevicesAsync.hasError && sortedItems.isEmpty) {
      return Center(
        child: _PanelMessage(
          icon: CupertinoIcons.exclamationmark_circle,
          title: context.l10n.t('adbUnavailable'),
          subtitle: activeDevicesAsync.error.toString(),
        ),
      );
    }
    if (activeDevicesAsync.isLoading && sortedItems.isEmpty) {
      return Center(
        child: _PanelMessage(
          icon: CupertinoIcons.arrow_2_circlepath,
          title: context.l10n.t('scanningDevices'),
          animateIcon: true,
        ),
      );
    }
    if (sortedItems.isEmpty) {
      return Center(
        child: _PanelMessage(
          icon: CupertinoIcons.slash_circle,
          title: context.l10n.t('noDevices'),
          subtitle: context.l10n.t('connectUsbOrTcp'),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: !hasBoundedHeight,
      physics: hasBoundedHeight ? null : const NeverScrollableScrollPhysics(),
      itemCount: sortedItems.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
      ),
      itemBuilder: (context, index) {
        final device = sortedItems[index];
        final isSelected = ref.watch(selectedDeviceProvider)?.id == device.id;
        return _buildDeviceRow(context, device, isSelected, isCompact);
      },
    );
  }

  Widget _buildTableHeader(
    BuildContext context,
    bool isCompact,
    bool allChecked,
    bool hasChecked,
  ) {
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (!isCompact) ...[
            SizedBox(
              width: 45,
              child: Checkbox(
                tristate: true,
                value: hasChecked && !allChecked ? null : allChecked,
                onChanged: (_) {
                  ref
                      .read(deviceRegistryProvider.notifier)
                      .toggleAll(!allChecked);
                },
              ),
            ),
            const SizedBox(width: 10),
          ],
          _SortableHeaderCell(
            flex: 3,
            label: context.l10n.t('deviceIdentifier'),
            style: titleStyle,
            sortIcon: _getSortIcon('id'),
            onTap: () => _toggleSort('id'),
          ),
          const SizedBox(width: 10),
          _SortableHeaderCell(
            flex: 3,
            label: context.l10n.t('deviceNameCol'),
            style: titleStyle,
            sortIcon: _getSortIcon('name'),
            onTap: () => _toggleSort('name'),
          ),
          const SizedBox(width: 10),
          _SortableHeaderCell(
            flex: 2,
            label: context.l10n.t('deviceStatusCol'),
            style: titleStyle,
            sortIcon: _getSortIcon('status'),
            onTap: () => _toggleSort('status'),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(context.l10n.t('deviceActionsCol'), style: titleStyle),
          ),
          if (!isCompact) ...[
            const SizedBox(width: 10),
            const SizedBox(
              width: 40,
              child: Icon(
                CupertinoIcons.settings,
                size: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _getSortIcon(String column) {
    if (_sortColumn != column) {
      return const Padding(
        padding: EdgeInsets.only(left: 4),
        child: Icon(
          CupertinoIcons.chevron_up_chevron_down,
          size: 14,
          color: Colors.grey,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(
        _sortAscending
            ? CupertinoIcons.chevron_up
            : CupertinoIcons.chevron_down,
        size: 14,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// 设备表头中带排序能力的单元格。
class _SortableHeaderCell extends StatelessWidget {
  const _SortableHeaderCell({
    required this.flex,
    required this.label,
    required this.style,
    required this.sortIcon,
    required this.onTap,
  });

  final int flex;
  final String label;
  final TextStyle? style;
  final Widget sortIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Text(label, style: style),
              sortIcon,
            ],
          ),
        ),
      ),
    );
  }
}
