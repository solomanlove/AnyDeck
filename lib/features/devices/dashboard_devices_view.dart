part of '../dashboard_screen.dart';

/// 设备列表主体布局：负责排序、空态、表头和 Card 容器。
extension _DeviceListPanelView on _DeviceListPanelState {
  Widget _buildDeviceListPanel(BuildContext context) {
    final activeDevicesAsync = ref.watch(discoveredDevicesProvider);
    final items = ref.watch(deviceRegistryProvider);
    final groups = ref.watch(deviceGroupsProvider).value ?? DeviceGroupsState();
    ref.listen(deviceRegistryProvider, (_, devices) {
      if (ref.read(deviceGroupsProvider).hasValue) {
        _synchronizeDeviceGroups(devices);
      }
    });
    ref.listen(deviceGroupsProvider, (previous, next) {
      if (previous?.hasValue != true && next.hasValue) {
        _synchronizeDeviceGroups(ref.read(deviceRegistryProvider));
      }
    });
    final airplayRoot = ref.watch(airplaySessionProvider);
    final mergedAirPlay = mergeAirPlayDevicesIntoList(items, airplayRoot);
    final selectedGroupId = groups.groups.any((group) => group.id == _groupId)
        ? _groupId : null;
    final groupedDevices = mergedAirPlay.devices
        .where((device) => groups.matches(selectedGroupId, device)).toList();
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
              groupedDevices,
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
                    l10n: context.l10n,
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
        final selectionBar = _batchMode
            ? _buildSelectionBar(context, selectable, checked)
            : null;
        final content = _buildDeviceListContent(
          context: context,
          activeDevicesAsync: activeDevicesAsync,
          sortedItems: sortedItems,
          names: names,
          sessionByDeviceId: mergedAirPlay.sessionByDeviceId,
          isCompact: windowWidth <= 730,
          hasBoundedHeight: constraints.hasBoundedHeight,
          selectionBar: selectionBar,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: constraints.hasBoundedHeight
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            // 筛选栏保留响应式留白，设备列表和设备墙占满下方内容区。
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _DeviceTableLayout.insetFor(windowWidth),
              ).copyWith(top: windowWidth <= 650 ? 10 : 12),
              child: DeviceListFilters(
                controller: _searchController,
                onlineCount: groupedDevices.where((d) => d.isOnline).length,
                totalCount: groupedDevices.length,
                groupFilter: DeviceGroupFilter(
                  selectedGroupId: selectedGroupId,
                  onChanged: _changeGroup,
                  // 临时 AirPlay 会话没有稳定物理身份，自定义成员只选注册设备。
                  devices: items,
                  names: names,
                ),
                filter: _filter,
                onFilterChanged: _changeFilter,
                viewMode: _viewMode,
                onViewModeChanged: _changeViewMode,
                batchMode: _batchMode,
                onBatchModeChanged: _changeBatchMode,
                onSearchChanged: _changeQuery,
              ),
            ),
            if (selectionBar != null &&
                (_viewMode == DeviceViewMode.wall || sortedItems.isEmpty))
              selectionBar,
            if (constraints.hasBoundedHeight)
              Expanded(child: content)
            else
              content,
          ],
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

      // 版本按数字分段比较；缺失版本始终位于当前在线/投屏优先级末尾。
      if (_sortColumn == 'systemVersion') {
        final cmp = DeviceSystemVersionSort.compare(
          a, b, ascending: _sortAscending,
        );
        return cmp != 0 ? cmp : a.id.compareTo(b.id);
      }

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
    required Widget? selectionBar,
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
      final filtered = _query.isNotEmpty ||
          _filter != DeviceStatusFilter.all || _groupId != null;
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
    final connectionWidth = _connectionColumnWidth(
      context,
      sortedItems,
      sessionByDeviceId,
    );
    return Padding(
      // 筛选组件已有 10px 底部留白，宽窗补齐到与顶部一致。
      padding: EdgeInsets.only(
        top: MediaQuery.sizeOf(context).width <= 650 ? 0 : 2,
      ),
      child: ClipRect(
        child: ColoredBox(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: hasBoundedHeight
                ? MainAxisSize.max
                : MainAxisSize.min,
            children: [
              // 管理模式直接复用表头位置，不再额外占据一行。
              if (selectionBar != null)
                selectionBar
              else if (MediaQuery.sizeOf(context).width > 490)
                _buildTableHeader(context, isCompact, connectionWidth),
              if (hasBoundedHeight)
                Expanded(
                  child: _buildRows(
                    sortedItems,
                    names,
                    sessionByDeviceId,
                    isCompact,
                    true,
                    connectionWidth,
                  ),
                )
              else
                _buildRows(
                  sortedItems,
                  names,
                  sessionByDeviceId,
                  isCompact,
                  false,
                  connectionWidth,
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
    double connectionWidth,
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
        connectionWidth: connectionWidth,
      );
    },
  );

  /// 只测量不同的通道组合，按可见设备的实际内容统一表头与行宽。
  double _connectionColumnWidth(
    BuildContext context,
    List<RegisteredDevice> devices,
    Map<String, AirPlaySessionData> sessions,
  ) {
    var width = 80.0;
    final measured = <String>{};
    for (final device in devices) {
      final channels = DeviceListPresentation.connections(
        device,
        isAirplayMirroring: sessions.containsKey(device.id),
      );
      if (!measured.add(channels.map((channel) => channel.index).join(','))) {
        continue;
      }
      width = max(
        width,
        DeviceConnectionIndicators.labelsWidth(context, channels) + 12,
      );
    }
    return width;
  }

  Widget _buildTableHeader(
    BuildContext context,
    bool compact,
    double connectionWidth,
  ) {
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
          connectionWidth,
        );
        return Container(
          key: const Key('deviceTableHeader'),
          constraints: BoxConstraints(
            minHeight: _DeviceTableLayout.headerHeight(context),
          ),
          padding: EdgeInsets.symmetric(horizontal: layout.horizontalInset),
          color: theme.appColors.sunkenSurface,
          child: Row(
            children: [
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (!layout.systemInline)
                _SortableHeaderCell(
                  key: const Key('deviceSystemVersionSort'),
                  flex: 1,
                  width: _DeviceTableLayout.systemWidth,
                  label: context.l10n.t('deviceAndroidVersionCol'),
                  style: style,
                  sortIcon: _getSortIcon('systemVersion'),
                  onTap: () => _toggleSort('systemVersion'),
                ),
              SizedBox(
                width: layout.actionsWidth,
                child: Text(
                  context.l10n.t('deviceActionsCol'),
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
/// [width] 指定固定列宽；为空时按 [flex] 分配剩余空间。
class _SortableHeaderCell extends StatelessWidget {
  const _SortableHeaderCell({
    super.key,
    required this.flex,
    this.width,
    required this.label,
    required this.style,
    required this.sortIcon,
    required this.onTap,
  });

  final int flex;
  final double? width;
  final String label;
  final TextStyle? style;
  final Widget sortIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.zero,
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
    );
    return width == null
        ? Expanded(flex: flex, child: content)
        : SizedBox(width: width, child: content);
  }
}
