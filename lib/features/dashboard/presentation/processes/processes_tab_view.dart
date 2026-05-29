part of 'processes_tab.dart';

/// 进程管理页的主布局，和进程筛选/排序状态分离维护。
extension _ProcessesTabView on _ProcessesTabState {
  Widget _buildProcessesTab(BuildContext context) {
    if (!widget.device.isOnline) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_off, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('手机离线，无法读取进程列表'),
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
                child: TextField(
                  controller: _filterController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: context.l10n.t('filterPackage'),
                    suffixIcon: _filter.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _filterController.clear();
                              _updateState(() => _filter = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) => _updateState(() => _filter = value),
                ),
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
              Container(
                height: 24,
                width: 1,
                color: Theme.of(context).dividerColor,
              ),
              const SizedBox(width: 8),
              processesAsync.when(
                data: (items) {
                  final filtered = _sortAndFilterProcesses(items, packages);
                  return Text(
                    context.l10n
                        .t('processCount')
                        .replaceAll('{count}', '${filtered.length}'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
                loading: () => const Text('读取中...'),
                error: (_, error) => const Text('加载失败'),
              ),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: '手动刷新进程',
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: _refreshing ? null : () => _refreshProcesses(),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close),
                style: IconButton.styleFrom(
                  backgroundColor: _selectedPid != null
                      ? Theme.of(context).colorScheme.errorContainer
                      : null,
                  foregroundColor: _selectedPid != null
                      ? Theme.of(context).colorScheme.onErrorContainer
                      : null,
                ),
                tooltip: '结束选中的进程',
                onPressed: _selectedPid != null ? _killProcess : null,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Process Table
          Expanded(
            child: processesAsync.when(
              loading: () => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在加载手机进程列表...'),
                  ],
                ),
              ),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text('加载进程列表失败: $error'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => _refreshProcesses(),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
              data: (items) {
                final filtered = _sortAndFilterProcesses(items, packages);

                if (filtered.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.list_alt_outlined,
                          size: 48,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text('未发现匹配的运行进程'),
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
                            _selectedProcess = null;
                          } else {
                            _selectedPid = process.pid;
                            _selectedProcess = process;
                          }
                        });
                      },
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
}
