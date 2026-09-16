part of '../dashboard_screen.dart';

enum AppFilterType { user, system, all, favorites }

class AppsTab extends ConsumerStatefulWidget {
  const AppsTab({super.key, required this.device});

  final AdbDevice device;

  @override
  ConsumerState<AppsTab> createState() => _AppsTabState();
}

/// 展示已安装应用，并提供包级操作。
class _AppsTabState extends ConsumerState<AppsTab> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  AppFilterType _appFilterType = AppFilterType.user;
  PackageRefreshProgress? _refreshProgress;
  String? _selectedPackage;
  bool _isGridView = false;
  double _gridItemSize = 100.0;
  final Set<String> _refreshingPackageDetails = <String>{};

  final FocusNode _filterFocusNode = FocusNode();
  final LayerLink _filterLayerLink = LayerLink();
  final GlobalKey _textFieldKey = GlobalKey();
  OverlayEntry? _filterOverlayEntry;

  @override
  void initState() {
    super.initState();
    _filterFocusNode.addListener(_onFilterFocusChange);
  }

  @override
  void dispose() {
    _hideFilterOverlay();
    _filterFocusNode.removeListener(_onFilterFocusChange);
    _filterFocusNode.dispose();
    _filterController.dispose();
    super.dispose();
  }

  void _onFilterFocusChange() {
    if (_filterFocusNode.hasFocus) {
      _showFilterOverlay();
    } else {
      // 失去焦点时的隐藏由 TapRegion 的 onTapOutside 处理
    }
  }

  void _showFilterOverlay() {
    _hideFilterOverlay();
    if (!mounted) return;

    final overlayState = Overlay.of(context);
    _filterOverlayEntry = OverlayEntry(
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final history = ref.watch(appsSearchHistoryProvider).value ?? [];
            return CompositedTransformFollower(
              link: _filterLayerLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 42),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: _getTextFieldWidth(),
                  child: TapRegion(
                    groupId: 'apps_search_filter_region',
                    onTapOutside: (event) {
                      _hideFilterOverlay();
                      _filterFocusNode.unfocus();
                    },
                    child: _buildDropdownOverlayContent(ref, history),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    overlayState.insert(_filterOverlayEntry!);
  }

  void _hideFilterOverlay() {
    _filterOverlayEntry?.remove();
    _filterOverlayEntry = null;
  }

  double _getTextFieldWidth() {
    final renderBox =
        _textFieldKey.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.size.width ?? 300.0;
  }

  void _applyFilter(String value) {
    _filterController.text = value;
    setState(() {
      _filter = value;
    });
    if (value.isNotEmpty) {
      ref.read(appsSearchHistoryProvider.notifier).add(value);
    }
  }

  Widget _buildDropdownOverlayContent(WidgetRef ref, List<String> history) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      color: isDark ? const Color(0xff1e293b) : Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
            width: 1,
          ),
        ),
        constraints: const BoxConstraints(maxHeight: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () {
                _applyFilter('debug');
                _hideFilterOverlay();
                _filterFocusNode.unfocus();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'DEBUG',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.l10n.t('filterDebugOnly'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
            if (history.isNotEmpty) ...[
              Divider(
                height: 1,
                color: isDark
                    ? const Color(0xff334155)
                    : const Color(0xffe2e8f0),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.l10n.t('searchHistory'),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        ref.read(appsSearchHistoryProvider.notifier).clear();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        context.l10n.t('clear'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final item = history[index];
                    return InkWell(
                      onTap: () {
                        _applyFilter(item);
                        _hideFilterOverlay();
                        _filterFocusNode.unfocus();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.clock,
                              size: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item,
                                style: Theme.of(context).textTheme.bodyMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(CupertinoIcons.clear, size: 14),
                              onPressed: () {
                                ref
                                    .read(appsSearchHistoryProvider.notifier)
                                    .remove(item);
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              splashRadius: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(deviceOnlineProvider(widget.device.id));
    final packages = ref.watch(packagesProvider(widget.device.id));
    final selectedPkgName = ref.watch(selectedAppPackageProvider);

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
        return _AppFunctionsView(
          deviceId: widget.device.id,
          package: selectedPackage,
          onBack: () {
            ref.read(selectedAppPackageProvider.notifier).state = null;
          },
        );
      } else if (packages.hasValue) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(selectedAppPackageProvider.notifier).state = null;
        });
      }
    }

    return DashboardTabLayout(
      toolbar: DashboardSearchToolbar<AppFilterType>(
        searchController: _filterController,
        searchHint: context.l10n.t('filterPackage'),
        searchFocusNode: _filterFocusNode,
        searchKey: _textFieldKey,
        searchTapRegionGroupId: 'apps_search_filter_region',
        hasSearchQuery: _filter.isNotEmpty,
        onSearchChanged: (value) => setState(() => _filter = value),
        onSearchClear: () {
          _filterController.clear();
          setState(() => _filter = '');
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
            setState(() => _appFilterType = value);
          }
        },
        trailingActions: [
          IconButton(
            tooltip: context.l10n.t('usageTitle'),
            icon: const Icon(CupertinoIcons.chart_bar, size: 20),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => UsageReportDialog(deviceId: widget.device.id),
            ),
          ),
          IconButton(
            tooltip: context.l10n.t('refreshPackages'),
            icon: const Icon(CupertinoIcons.refresh, size: 20),
            onPressed: (isOnline && _refreshProgress == null)
                ? _refreshPackages
                : null,
          ),
          IconButton(
            tooltip: context.l10n.t('zoomIn'),
            icon: const Icon(CupertinoIcons.zoom_in, size: 20),
            onPressed: (_isGridView && _gridItemSize < 160.0)
                ? () => setState(
                    () => _gridItemSize = min(160.0, _gridItemSize + 15.0),
                  )
                : null,
          ),
          IconButton(
            tooltip: context.l10n.t('zoomOut'),
            icon: const Icon(CupertinoIcons.zoom_out, size: 20),
            onPressed: (_isGridView && _gridItemSize > 70.0)
                ? () => setState(
                    () => _gridItemSize = max(70.0, _gridItemSize - 15.0),
                  )
                : null,
          ),
          IconButton(
            tooltip: context.l10n.t('gridView'),
            icon: const Icon(CupertinoIcons.square_grid_2x2, size: 20),
            isSelected: _isGridView,
            selectedIcon: const Icon(
              CupertinoIcons.square_grid_2x2_fill,
              size: 20,
            ),
            onPressed: () => setState(() => _isGridView = true),
          ),
          IconButton(
            tooltip: context.l10n.t('listView'),
            icon: const Icon(CupertinoIcons.list_bullet, size: 20),
            isSelected: !_isGridView,
            selectedIcon: const Icon(CupertinoIcons.list_bullet, size: 20),
            onPressed: () => setState(() => _isGridView = false),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(CupertinoIcons.square_arrow_down),
            label: Text(context.l10n.t('installApk')),
            onPressed: _installApk,
          ),
        ],
      ),
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
                final selectedPackage = _selectedVisiblePackage(filtered);
                final showActionsRow = _isGridView || selectedPackage != null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showActionsRow) ...[
                      Row(
                        children: [
                          if (_isGridView)
                            Expanded(
                              child: Text(
                                context.l10n
                                    .t('appCount')
                                    .replaceAll(
                                      '{visible}',
                                      '${filtered.length}',
                                    )
                                    .replaceAll('{total}', '${items.length}'),
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            )
                          else
                            const Spacer(),
                          if (selectedPackage != null)
                            _PackageActions(
                              deviceId: widget.device.id,
                              package: selectedPackage,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Expanded(
                      child: _isGridView
                          ? _PackageGrid(
                              deviceId: widget.device.id,
                              packages: filtered,
                              selectedPackage: _selectedPackage,
                              onSelected: _selectPackage,
                              onOpened: _openPackage,
                              gridItemSize: _gridItemSize,
                            )
                          : _PackageTable(
                              deviceId: widget.device.id,
                              packages: filtered,
                              totalCount: items.length,
                              selectedPackage: _selectedPackage,
                              onSelected: _selectPackage,
                              onOpened: _openPackage,
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
                  title: Text(context.l10n.t('packageRefreshTitle')),
                  content: PackageRefreshView(progress: _refreshProgress!),
                  actions: [
                    Visibility(
                      visible: _refreshProgress!.finished,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: TextButton(
                        onPressed: () =>
                            setState(() => _refreshProgress = null),
                        child: Text(context.l10n.t('close')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ), // Stack
    ); // DashboardTabLayout
  }

  /// 对应用名和包名执行大小写不敏感筛选，并且支持拼音匹配（全拼、首字母），可按用户应用/系统应用/全部筛选。
  List<AdbPackage> _filterPackages(List<AdbPackage> items) {
    final filter = _filter.trim().toLowerCase();
    final cleanFilter = filter.replaceAll(' ', '');
    return items
        .where((package) {
          switch (_appFilterType) {
            case AppFilterType.user:
              return !package.system;
            case AppFilterType.system:
              return package.system;
            case AppFilterType.all:
              return true;
            case AppFilterType.favorites:
              final favs = ref.watch(appFavoritesProvider).value ?? const <String>{};
              return favs.contains(package.name);
          }
        })
        .where((package) {
          if (filter.isEmpty) {
            return true;
          }

          // 如果搜索关键词中包含 'debug'，则匹配所有带 DEBUG 标签（debuggable 为 true）的应用
          if (filter.contains('debug') && package.debuggable) {
            return true;
          }

          final nameMatch = package.name.toLowerCase().contains(filter);
          final displayNameMatch = package.displayName.toLowerCase().contains(
            filter,
          );
          final versionMatch = package.versionLabel.toLowerCase().contains(
            filter,
          );

          if (nameMatch || displayNameMatch || versionMatch) {
            return true;
          }

          // 拼音筛选：全拼和首字母匹配（忽略空格）
          final displayNamePinyin = PinyinHelper.getPinyin(
            package.displayName,
            separator: '',
            format: PinyinFormat.WITHOUT_TONE,
          ).toLowerCase().replaceAll(' ', '');

          final displayNameShortPinyin = PinyinHelper.getShortPinyin(
            package.displayName,
          ).toLowerCase().replaceAll(' ', '');

          return displayNamePinyin.contains(cleanFilter) ||
              displayNameShortPinyin.contains(cleanFilter);
        })
        .toList(growable: false);
  }

  Widget _buildAppFilterSegment(String label, AppFilterType type) {
    final isSelected = _appFilterType == type;
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

  AdbPackage? _selectedVisiblePackage(List<AdbPackage> packages) {
    final selected = _selectedPackage;
    if (selected == null) {
      return null;
    }
    for (final package in packages) {
      if (package.name == selected) {
        return package;
      }
    }
    return null;
  }

  /// 单击选中应用时按需刷新详情和图标，但不进入应用详情页。
  Future<void> _selectPackage(String packageName) async {
    setState(() => _selectedPackage = packageName);
    if (!ref.read(deviceOnlineProvider(widget.device.id))) {
      return;
    }
    if (!_refreshingPackageDetails.add(packageName)) {
      return;
    }
    try {
      await ref
          .read(packagesProvider(widget.device.id).notifier)
          .refreshSinglePackage(packageName);
    } catch (error) {
      if (mounted) {
        _showSnack(context, error.toString(), isError: true);
      }
    } finally {
      _refreshingPackageDetails.remove(packageName);
    }
  }

  /// 双击应用时复用现有详情页入口，并保留当前列表选中态。
  void _openPackage(String packageName) {
    unawaited(_selectPackage(packageName));
    ref.read(selectedAppPackageProvider.notifier).state = packageName;
  }

  /// 打开宿主机文件选择器并安装选中的 APK。
  Future<void> _installApk() async {
    const group = XTypeGroup(label: 'APK', extensions: ['apk']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null || !mounted) {
      return;
    }
    final result = await ref
        .read(appManagementServiceProvider)
        .installApk(widget.device.id, file.path);
    if (!mounted) {
      return;
    }
    _showSnack(context, result.message, isError: !result.isSuccess);
    if (result.isSuccess) {
      await _refreshPackages();
    }
  }

  /// 手动刷新全部应用时，清空本地缓存并分批加载所有应用图标。
  Future<void> _refreshPackages() async {
    if (_refreshProgress != null) {
      return;
    }
    _hideFilterOverlay();
    _filterFocusNode.unfocus();
    setState(() => _refreshProgress = const PackageRefreshProgress());
    final notifier = ref.read(packagesProvider(widget.device.id).notifier);
    try {
      await notifier.refreshAllPackagesWithIcons(
        onProgress: (progress) {
          if (mounted) {
            setState(() => _refreshProgress = progress);
          }
        },
      );
      if (mounted) {
        if (_refreshProgress?.stage != PackageRefreshStage.failed &&
            _refreshProgress?.failed == 0) {
          setState(() => _refreshProgress = null);
        } else if (_refreshProgress != null && !_refreshProgress!.finished) {
          setState(
            () => _refreshProgress = _refreshProgress!.atStage(
              PackageRefreshStage.completed,
            ),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _refreshProgress = _refreshProgress?.atStage(
            PackageRefreshStage.failed,
            error: error.toString(),
          );
        });
      }
    }
  }
}

/// 桌面风格的应用表格，包含元数据列和行操作。
