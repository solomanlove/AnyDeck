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

    // Resolve list of packages
    final List<AdbPackage> packages = packagesAsync.value ?? [];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Top Action Bar
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _filterController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        CupertinoIcons.line_horizontal_3_decrease,
                        size: 16,
                      ),
                      hintText: context.l10n.t('filterPackage'),
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
                      suffixIcon: _filter.isNotEmpty
                          ? IconButton(
                              icon: const Icon(CupertinoIcons.clear, size: 16),
                              onPressed: () {
                                _filterController.clear();
                                _updateState(() => _filter = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) => _updateState(() => _filter = value),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              CupertinoSlidingSegmentedControl<ProcessFilterType>(
                groupValue: _processFilterType,
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5)
                    : const Color(0xFFF1F5F9),
                thumbColor: Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context).colorScheme.surfaceContainerHigh
                    : Colors.white,
                padding: const EdgeInsets.all(3),
                children: {
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
                onValueChanged: (value) {
                  if (value != null) {
                    _updateState(() => _processFilterType = value);
                  }
                },
              ),
              const SizedBox(width: 12),
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
          const SizedBox(height: 12),

          // Process Table
          Expanded(
            child: processesAsync.when(
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
            ),
          ),
        ],
      ),
    );
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
