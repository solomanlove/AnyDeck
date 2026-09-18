part of 'processes_tab.dart';

/// 进程管理页的主布局，和进程筛选/排序状态分离维护。
extension _ProcessesTabView on _ProcessesTabState {
  Widget _buildProcessesTab(BuildContext context) {
    final isOnline = ref.watch(deviceOnlineProvider(widget.device.id));
    if (!isOnline) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.bolt_slash, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(context.l10n.t('offlineProcessWarning')),
          ],
        ),
      );
    }

    final processesAsync = ref.watch(processesProvider(widget.device.id));
    final packagesAsync = ref.watch(packagesProvider(widget.device.id));
    final searchHistory =
        ref.watch(processesSearchHistoryProvider).value ?? const <String>[];

    // Resolve list of packages
    final List<AdbPackage> packages = packagesAsync.value ?? [];

    return DashboardTabLayout(
      toolbar: DashboardSearchToolbar<ProcessFilterType>(
        searchController: _filterController,
        searchHint: context.l10n.t('filterPackage'),
        hasSearchQuery: _filter.isNotEmpty,
        onSearchChanged: (value) => _updateState(() => _filter = value),
        onSearchSubmitted: (value) =>
            ref.read(processesSearchHistoryProvider.notifier).add(value),
        searchHistory: searchHistory,
        onSearchHistorySelected: (value) =>
            ref.read(processesSearchHistoryProvider.notifier).add(value),
        onSearchHistoryRemoved: (value) =>
            ref.read(processesSearchHistoryProvider.notifier).remove(value),
        onSearchClear: () {
          _filterController.clear();
          _updateState(() => _filter = '');
        },
        segments: {
          ProcessFilterType.user: _buildProcessFilterSegment(
            context.l10n.t('userProcesses'),
            ProcessFilterType.user,
          ),
          ProcessFilterType.system: _buildProcessFilterSegment(
            context.l10n.t('systemProcesses'),
            ProcessFilterType.system,
          ),
          ProcessFilterType.all: _buildProcessFilterSegment(
            context.l10n.t('allProcesses'),
            ProcessFilterType.all,
          ),
        },
        currentSegment: _processFilterType,
        onSegmentChanged: (value) {
          if (value != null) {
            _updateState(() => _processFilterType = value);
          }
        },
        trailingActions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _onlyShowApps,
                onChanged: (value) =>
                    _updateState(() => _onlyShowApps = value ?? true),
              ),
              Text(context.l10n.t('onlyShowApps')),
            ],
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _onlyShowDebug,
                onChanged: (value) =>
                    _updateState(() => _onlyShowDebug = value ?? false),
              ),
              const Text('仅 Debug 应用'),
            ],
          ),
          const SizedBox(width: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(value: _autoRefresh, onChanged: _toggleAutoRefresh),
              Text(
                context.l10n
                    .t('autoRefreshInterval')
                    .replaceAll('{seconds}', '3'),
              ),
            ],
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: context.l10n.t('refreshProcessesTooltip'),
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(CupertinoIcons.refresh, size: 20),
            onPressed: _refreshing ? null : () => _refreshProcesses(),
          ),
        ],
      ),
      body: processesAsync.when(
        loading: () => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(context.l10n.t('loadingProcessList')),
            ],
          ),
        ),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_circle,
                size: 48,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n
                    .t('loadProcessListFailed')
                    .replaceAll('{error}', error.toString()),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _refreshProcesses(),
                child: Text(context.l10n.t('retry')),
              ),
            ],
          ),
        ),
        data: (items) {
          final filtered = _sortAndFilterProcesses(items, packages);

          if (filtered.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    CupertinoIcons.list_bullet,
                    size: 48,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(context.l10n.t('noMatchingProcesses')),
                ],
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final widths = _ProcessTableWidths.adaptive(
                viewportWidth: constraints.maxWidth,
              );

              return _ProcessTable(
                deviceId: widget.device.id,
                processes: filtered,
                packages: packages,
                selectedPid: _selectedPid,
                widths: widths,
                sortColumn: _sortColumn,
                sortAscending: _sortAscending,
                onSort: _onSort,
                onSelected: (process) {
                  _updateState(() {
                    if (_selectedPid == process.pid) {
                      _selectedPid = null;
                    } else {
                      _selectedPid = process.pid;
                    }
                  });
                },
                onContextMenuRequested: _showProcessContextMenu,
              );
            },
          );
        },
      ), // when
    ); // DashboardTabLayout
  }

  Widget _buildProcessFilterSegment(String label, ProcessFilterType type) {
    final isSelected = _processFilterType == type;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
