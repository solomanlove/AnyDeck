part of '../dashboard_screen.dart';

/// 应用页布局：单应用操作通过右键菜单展示，网格仅保留计数和缩放。
extension _AppsTabView on _AppsTabState {
  Widget _buildAppsTab(BuildContext context) {
    final isOnline = ref.watch(deviceOnlineProvider(widget.device.id));
    final packages = ref.watch(packagesProvider(widget.device.id));
    final selectedPkgName = ref.watch(selectedAppPackageProvider);
    final history = ref.watch(appsSearchHistoryProvider).value ?? const <String>[];

    if (selectedPkgName != null) {
      final selectedPackage = packages.maybeWhen(
        data: (items) {
          try {
            return items.firstWhere((p) => p.name == selectedPkgName);
          } catch (_) {
            return null;
          }
        },
        orElse: () => null,
      );

      if (selectedPackage != null) {
        if (widget.device.isHarmony) {
          final detail =
              _harmonyDetails[_harmonyDetailKey(selectedPackage.name)];
          if (detail != null) {
            return _HarmonyAppAnalysisView(
              package: selectedPackage,
              initialDetail: detail,
              onBack: _closeAppDetails,
              onReload: () => _loadHarmonyDetail(selectedPackage.name),
            );
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_openPackage(selectedPackage.name));
          });
        } else {
          return _AppFunctionsView(
            deviceId: widget.device.id,
            package: selectedPackage,
            onBack: _closeAppDetails,
          );
        }
      } else if (packages.hasValue) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _closeAppDetails();
        });
      }
    }

    return DashboardTabLayout(
      toolbar: DashboardSearchToolbar<AppFilterType>(
        searchController: _filterController,
        searchHint: context.l10n.t('filterPackage'),
        hasSearchQuery: _filter.isNotEmpty,
        onSearchChanged: (value) => _updateAppView(() => _filter = value),
        onSearchSubmitted: _commitFilter,
        onSearchHistorySelected: _commitFilter,
        onSearchHistoryRemoved: (value) =>
            ref.read(appsSearchHistoryProvider.notifier).remove(value),
        onSearchHistoryCleared: () =>
            ref.read(appsSearchHistoryProvider.notifier).clear(),
        searchHistory: history
            .where((item) => item.toLowerCase() != 'debug')
            .toList(growable: false),
        searchDefaultOptions: [
          DashboardHistoryOption(
            value: 'debug',
            label: context.l10n.t('filterDebugOnly'),
          ),
        ],
        onSearchClear: () {
          _filterController.clear();
          _updateAppView(() => _filter = '');
        },
        segments: {
          AppFilterType.user: _buildAppFilterSegment(
            context.l10n.t('userApps'),
            AppFilterType.user,
          ),
          AppFilterType.system: _buildAppFilterSegment(
            context.l10n.t('systemApps'),
            AppFilterType.system,
          ),
          AppFilterType.all: _buildAppFilterSegment(
            context.l10n.t('allApps'),
            AppFilterType.all,
          ),
          AppFilterType.favorites: _buildAppFilterSegment(
            '收藏 ✨',
            AppFilterType.favorites,
          ),
        },
        currentSegment: _appFilterType,
        onSegmentChanged: (value) {
          if (value != null) {
            _updateAppView(() => _appFilterType = value);
          }
        },
        trailingActions: [
          // 鸿蒙设备暂不支持基于 Companion 的使用时长统计功能
          if (!widget.device.isHarmony)
            IconButton(
              tooltip: context.l10n.t('usageTitle'),
              icon: const Icon(CupertinoIcons.chart_bar, size: 20),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => UsageReportDialog(deviceId: widget.device.id),
              ),
            ),
          IconButton(
            tooltip: _refreshTooltip,
            icon: const Icon(CupertinoIcons.refresh, size: 20),
            onPressed: (isOnline && _refreshProgress == null)
                ? _refreshPackages
                : null,
          ),
          AppsViewModeButton(
            key: const Key('appsGridViewButton'),
            tooltip: context.l10n.t('gridView'),
            icon: AppNavigationIcons.apps,
            selected: _isGridView,
            onPressed: () => _updateAppView(() => _isGridView = true),
          ),
          AppsViewModeButton(
            key: const Key('appsListViewButton'),
            tooltip: context.l10n.t('listView'),
            icon: CupertinoIcons.list_bullet,
            selected: !_isGridView,
            onPressed: () => _updateAppView(() => _isGridView = false),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(CupertinoIcons.square_arrow_down),
            label: Text(
              context.l10n.t(widget.device.isHarmony ? 'installHap' : 'installApk'),
            ),
            onPressed: _installPackage,
          ),
        ],
      ),
      belowToolbar: widget.device.isHarmony || widget.device.isIos
          ? null
          : FusionModeSettingRow(deviceId: widget.device.id),
      body: Stack(
        children: [
          Positioned.fill(
            child: packages.when(
              loading: () => _PanelMessage(
                icon: CupertinoIcons.arrow_2_circlepath,
                title: context.l10n.t('loadingPackages'),
                animateIcon: true,
              ),
              error: (error, stackTrace) => _PanelMessage(
                icon: CupertinoIcons.exclamationmark_circle,
                title: context.l10n.t('packageListFailed'),
                subtitle: error.toString(),
              ),
              data: (items) {
                final filtered = _filterPackages(items);
                if (filtered.isEmpty) {
                  return _PanelMessage(
                    icon: CupertinoIcons.square_grid_2x2,
                    title: context.l10n.t('noPackages'),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.device.isHarmony || _checkedPackages.isNotEmpty) ...[
                      _AppsBatchActionsToolbar(
                        deviceId: widget.device.id,
                        checkedPackages: _checkedPackages,
                        allFilteredPackages: filtered,
                        progressNotifier: _batchProgressNotifier,
                        onClearSelection: _clearCheckedPackages,
                        onSelectAll: () =>
                            _toggleCheckAllPackages(filtered),
                        isHarmony: widget.device.isHarmony,
                      ),
                      const SizedBox(height: 8),
                    ] else if (_isGridView) ...[
                      Row(
                        children: [
                          if (_isGridView)
                            Text(
                              context.l10n
                                  .t('appCount')
                                  .replaceAll(
                                    '{visible}',
                                    '${filtered.length}',
                                  )
                                  .replaceAll('{total}', '${items.length}'),
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          const Spacer(),
                          if (_isGridView) ...[
                            IconButton(
                              tooltip: context.l10n.t('zoomIn'),
                              icon: const Icon(CupertinoIcons.zoom_in, size: 20),
                              visualDensity: VisualDensity.compact,
                              onPressed: _gridItemSize < 160.0
                                  ? () => _updateAppView(
                                      () => _gridItemSize =
                                          min(160.0, _gridItemSize + 15.0),
                                    )
                                  : null,
                            ),
                            IconButton(
                              tooltip: context.l10n.t('zoomOut'),
                              icon: const Icon(CupertinoIcons.zoom_out, size: 20),
                              visualDensity: VisualDensity.compact,
                              onPressed: _gridItemSize > 70.0
                                  ? () => _updateAppView(
                                      () => _gridItemSize =
                                          max(70.0, _gridItemSize - 15.0),
                                    )
                                  : null,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Expanded(
                      child: _isGridView
                          ? _PackageGrid(
                              deviceId: widget.device.id,
                              isHarmony: widget.device.isHarmony,
                              packages: filtered,
                              selectedPackage: _selectedPackage,
                              checkedPackages: _checkedPackages,
                              onToggleCheck: _toggleCheckPackage,
                              onOpened: _openPackage,
                              onContextMenuRequested: _showAppContextMenu,
                              gridItemSize: _gridItemSize,
                            )
                          : _PackageTable(
                              deviceId: widget.device.id,
                              isHarmony: widget.device.isHarmony,
                              packages: filtered,
                              totalCount: items.length,
                              selectedPackage: _selectedPackage,
                              checkedPackages: _checkedPackages,
                              onToggleCheck: _toggleCheckPackage,
                              onToggleCheckAll: () =>
                                  _toggleCheckAllPackages(filtered),
                              onOpened: _openPackage,
                              onContextMenuRequested: _showAppContextMenu,
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (_refreshProgress != null)
            Positioned.fill(
              child: Container(
                color: Theme.of(
                  context,
                ).scaffoldBackgroundColor.withValues(alpha: 0.8),
                alignment: Alignment.center,
                child: AlertDialog(
                  title: Text(
                    _getRefreshTitle(_refreshingFilterType ?? _appFilterType),
                  ),
                  content: PackageRefreshView(progress: _refreshProgress!),
                  actions: [
                    Visibility(
                      visible: _refreshProgress!.finished,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: TextButton(
                        onPressed: () => _updateAppView(() {
                          _refreshProgress = null;
                          _refreshingFilterType = null;
                        }),
                        child: Text(context.l10n.t('close')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned.fill(
            child: ValueListenableBuilder<_BatchProgressState?>(
              valueListenable: _batchProgressNotifier,
              builder: (context, progress, _) {
                return IgnorePointer(
                  ignoring: progress == null,
                  child: progress == null
                      ? const SizedBox.shrink()
                      : Container(
                          color: Theme.of(context)
                              .scaffoldBackgroundColor
                              .withValues(alpha: 0.8),
                          alignment: Alignment.center,
                          child: _AppsBatchProgressCard(state: progress),
                        ),
                );
              },
            ),
          ),
        ],
      ), // Stack
    ); // DashboardTabLayout
  }

}
