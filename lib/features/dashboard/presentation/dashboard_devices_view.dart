part of 'dashboard_screen.dart';

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

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildToolbar(context, hasChecked, selectedCount),
                const SizedBox(height: 16),
                _buildTableHeader(context, isCompact, allChecked, hasChecked),
                const SizedBox(height: 8),
                if (hasBoundedHeight)
                  Expanded(child: contentWidget)
                else
                  contentWidget,
              ],
            ),
          ),
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

  Widget _buildToolbar(
    BuildContext context,
    bool hasChecked,
    int selectedCount,
  ) {
    return Row(
      children: [
        Text(
          context.l10n.t('devices'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Spacer(),
        Tooltip(
          message: context.l10n.t('deleteSelectedDevices'),
          child: IconButton.filledTonal(
            icon: const Icon(Icons.delete_sweep_outlined),
            color: Colors.redAccent,
            onPressed: hasChecked
                ? () => _deleteSelectedDevices(context, selectedCount)
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: context.l10n.t('connectTcp'),
          child: IconButton.filledTonal(
            icon: const Icon(Icons.add_link),
            onPressed: () => _showConnectDialog(context),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: context.l10n.t('pairDeviceTitle'),
          child: IconButton.filledTonal(
            icon: const Icon(Icons.sensors),
            onPressed: () => _showPairingDialog(context),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: context.l10n.t('refreshDevices'),
          child: IconButton.filledTonal(
            icon: const Icon(Icons.refresh),
            onPressed: () => _refreshDevices(context, ref),
          ),
        ),
      ],
    );
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
          icon: Icons.error_outline,
          title: context.l10n.t('adbUnavailable'),
          subtitle: activeDevicesAsync.error.toString(),
        ),
      );
    }
    if (activeDevicesAsync.isLoading && sortedItems.isEmpty) {
      return Center(
        child: _PanelMessage(
          icon: Icons.sync,
          title: context.l10n.t('scanningDevices'),
        ),
      );
    }
    if (sortedItems.isEmpty) {
      return Center(
        child: _PanelMessage(
          icon: Icons.usb_off_outlined,
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
              child: Icon(Icons.settings, size: 16, color: Colors.grey),
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
        child: Icon(Icons.unfold_more, size: 14, color: Colors.grey),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(
        _sortAscending ? Icons.expand_less : Icons.expand_more,
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
