part of '../dashboard_screen.dart';

/// 设备列表主体布局：负责排序、空态、表头和 Card 容器。
extension _DeviceListPanelView on _DeviceListPanelState {
  Widget _buildDeviceListPanel(BuildContext context) {
    final activeDevicesAsync = ref.watch(discoveredDevicesProvider);
    final items = ref.watch(deviceRegistryProvider);
    final airplayRoot = ref.watch(airplaySessionProvider);
    final mergedAirPlay = mergeAirPlayDevicesIntoList(items, airplayRoot);
    final names = {
      for (final device in mergedAirPlay.devices)
        device.id: DeviceListPresentation.name(
          device,
          ref.watch(
            cachedDeviceOverviewProvider(
              device.id,
            ).select((value) => value.value?.name),
          ),
        ),
    };
    final sortedItems =
        _sortedDevices(
              mergedAirPlay.devices,
              mergedAirPlay.sessionByDeviceId,
              names,
            )
            .where(
              (device) =>
                  (_filter == DeviceStatusFilter.all ||
                      device.isOnline ==
                          (_filter == DeviceStatusFilter.online)) &&
                  DeviceListPresentation.matches(
                    device,
                    names[device.id]!,
                    _query,
                    false,
                  ),
            )
            .toList();
    final selectable = sortedItems
        .where((device) => !device.id.startsWith('airplay-'))
        .toList();
    final checked = items.where((device) => device.isChecked).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final windowWidth = MediaQuery.sizeOf(context).width;
        final content = _buildDeviceListContent(
          context: context,
          activeDevicesAsync: activeDevicesAsync,
          sortedItems: sortedItems,
          names: names,
          sessionByDeviceId: mergedAirPlay.sessionByDeviceId,
          isCompact: windowWidth <= 730,
          hasBoundedHeight: constraints.hasBoundedHeight,
        );
        return Padding(
          padding: windowWidth <= 490
              ? const EdgeInsets.fromLTRB(8, 10, 8, 0)
              : windowWidth <= 650
              ? const EdgeInsets.fromLTRB(12, 10, 12, 0)
              : const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: constraints.hasBoundedHeight
                ? MainAxisSize.max
                : MainAxisSize.min,
            children: [
              DeviceListFilters(
                controller: _searchController,
                onlineCount: mergedAirPlay.devices
                    .where((d) => d.isOnline)
                    .length,
                totalCount: mergedAirPlay.devices.length,
                filter: _filter,
                onFilterChanged: _changeFilter,
                viewMode: _viewMode,
                onViewModeChanged: _changeViewMode,
                batchMode: _batchMode,
                onBatchModeChanged: _changeBatchMode,
                onSearchChanged: _changeQuery,
              ),
              if (_batchMode) _buildSelectionBar(context, selectable, checked),
              if (constraints.hasBoundedHeight)
                Expanded(child: content)
              else
                content,
            ],
          ),
        );
      },
    );
  }

  List<RegisteredDevice> _sortedDevices(
    List<RegisteredDevice> items, [
    Map<String, AirPlaySessionData> sessionByDeviceId = const {},
    Map<String, String> names = const {},
  ]) {
    final sortedItems = List<RegisteredDevice>.from(items);
    sortedItems.sort((a, b) {
      // 在线设备始终置顶，避免离线历史记录打断当前调试流程。
      if (a.isOnline && !b.isOnline) return -1;
      if (!a.isOnline && b.isOnline) return 1;

      // AirPlay 正在投屏的设备在在线列表中优先展示
      final aMirroring = sessionByDeviceId.containsKey(a.id);
      final bMirroring = sessionByDeviceId.containsKey(b.id);
      if (aMirroring && !bMirroring) return -1;
      if (!aMirroring && bMirroring) return 1;

      final cmp = switch (_sortColumn) {
        'name' => (names[a.id] ?? a.displayName).compareTo(names[b.id] ?? b.displayName),
        'status' => a.status.compareTo(b.status),
        _ => a.id.compareTo(b.id),
      };
      return _sortAscending ? cmp : -cmp;
    });
    return sortedItems;
  }

  Widget _buildDeviceListContent({
    required BuildContext context,
    required AsyncValue<List<DiscoveredDevice>> activeDevicesAsync,
    required List<RegisteredDevice> sortedItems,
    required Map<String, String> names,
    required Map<String, AirPlaySessionData> sessionByDeviceId,
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
      final filtered = _query.isNotEmpty || _filter != DeviceStatusFilter.all;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PanelMessage(
              icon: CupertinoIcons.slash_circle,
              title: context.l10n.t(
                filtered ? 'deviceListNoMatches' : 'noDevices',
              ),
              subtitle: context.l10n.t(
                filtered ? 'deviceListResetHint' : 'connectUsbOrTcp',
              ),
            ),
            if (filtered) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('deviceResetFilters'),
                onPressed: _resetDeviceFilters,
                child: Text(context.l10n.t('deviceWorkspaceResetFilters')),
              ),
            ],
          ],
        ),
      );
    }

    if (_viewMode == DeviceViewMode.wall) {
      return _buildDeviceWall(
        sortedItems,
        names,
        sessionByDeviceId,
        hasBoundedHeight: hasBoundedHeight,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: ClipRRect(
        borderRadius: AppThemeSizes.radiusLarge,
        child: ColoredBox(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: hasBoundedHeight
                ? MainAxisSize.max
                : MainAxisSize.min,
            children: [
              if (MediaQuery.sizeOf(context).width > 490)
                _buildTableHeader(context, isCompact),
              if (hasBoundedHeight)
                Expanded(
                  child: _buildRows(
                    sortedItems,
                    names,
                    sessionByDeviceId,
                    isCompact,
                    true,
                  ),
                )
              else
                _buildRows(
                  sortedItems,
                  names,
                  sessionByDeviceId,
                  isCompact,
                  false,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRows(
    List<RegisteredDevice> devices,
    Map<String, String> names,
    Map<String, AirPlaySessionData> sessions,
    bool compact,
    bool bounded,
  ) => ListView.builder(
    shrinkWrap: !bounded,
    physics: bounded ? null : const NeverScrollableScrollPhysics(),
    itemCount: devices.length,
    itemBuilder: (context, index) {
      final device = devices[index];
      return _buildDeviceRow(
        context,
        device,
        _contextDeviceId == device.id,
        compact,
        index,
        airplaySession: sessions[device.id],
        displayName: names[device.id]!,
      );
    },
  );

  Widget _buildTableHeader(BuildContext context, bool compact) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _DeviceTableLayout.resolve(
          context,
          constraints.maxWidth,
          _batchMode,
        );
        return Container(
          key: const Key('deviceTableHeader'),
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        color: theme.appColors.sunkenSurface,
          child: Row(
            children: [
              if (_batchMode) const SizedBox(width: 36),
              _SortableHeaderCell(
                flex: 1,
                label: context.l10n.t('deviceNameCol'),
                style: style,
                sortIcon: _getSortIcon('name'),
                onTap: () => _toggleSort('name'),
              ),
              if (!layout.statusInline)
                SizedBox(
                  width: layout.statusWidth,
                  child: Text(
                    context.l10n.t('deviceWorkspaceConnectionStatus'),
                    style: style,
                  ),
                ),
              if (!layout.systemInline)
                SizedBox(
                  width: _DeviceTableLayout.systemWidth,
                  child: Text(
                    context.l10n.t('deviceAndroidVersionCol'),
                    style: style,
                  ),
                ),
              if (!_batchMode)
                SizedBox(
                  width: layout.actionsWidth,
                  child: Text(
                    context.l10n.t('deviceActionsCol'),
                    style: style,
                    textAlign: TextAlign.right,
                  ),
                ),
            ],
          ),
        );
      },
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
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: style,
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
