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
  final Set<String> _analyzingHarmonyPackages = <String>{};
  final Map<String, HarmonyAppDetail> _harmonyDetails =
      <String, HarmonyAppDetail>{};

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  /// 搜索历史只记录实际提交的文本，DEBUG 保持为固定快捷选项。
  void _commitFilter(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    if (query.toLowerCase() == 'debug') {
      setState(() => _appFilterType = AppFilterType.all);
      return;
    }
    ref.read(appsSearchHistoryProvider.notifier).add(query);
  }

  @override
  Widget build(BuildContext context) {
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
              onBack: () {
                ref.read(selectedAppPackageProvider.notifier).state = null;
              },
              onReload: () => _loadHarmonyDetail(selectedPackage.name),
            );
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(selectedAppPackageProvider.notifier).state = null;
          });
        } else {
          return _AppFunctionsView(
            deviceId: widget.device.id,
            package: selectedPackage,
            onBack: () {
              ref.read(selectedAppPackageProvider.notifier).state = null;
            },
          );
        }
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
        hasSearchQuery: _filter.isNotEmpty,
        onSearchChanged: (value) => setState(() => _filter = value),
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
                              onOpenDetails: () =>
                                  _openPackage(selectedPackage.name),
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

          // DEBUG 快捷项只匹配 debuggable 应用，不与普通名称搜索混用。
          if (filter == 'debug') return package.debuggable;

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
    // HarmonyOS 单击只更新选中态，避免不支持 `bm dump` 的应用被误判为卸载。
    if (widget.device.isHarmony) {
      return;
    }
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

  /// 双击 HarmonyOS 应用时先验证 `bm dump`，不支持分析则停留在列表页。
  Future<void> _openPackage(String packageName) async {
    if (!widget.device.isHarmony) {
      // Android 保持原有行为：后台刷新单包信息并立即进入现有详情页。
      unawaited(_selectPackage(packageName));
      ref.read(selectedAppPackageProvider.notifier).state = packageName;
      return;
    }

    final deviceId = widget.device.id;
    setState(() => _selectedPackage = packageName);
    if (!mounted) return;
    if (!_analyzingHarmonyPackages.add(packageName)) return;
    _showSnack(context, context.l10n.t('harmonyAnalysisLoading'));
    try {
      await _loadHarmonyDetail(packageName);
    } catch (error) {
      if (mounted) {
        _showSnack(
          context,
          context.l10n
              .t('harmonyAnalysisFailed')
              .replaceAll('{error}', error.toString()),
          isError: true,
        );
      }
      return;
    } finally {
      _analyzingHarmonyPackages.remove(packageName);
    }
    if (!mounted || widget.device.id != deviceId) return;
    ref.read(selectedAppPackageProvider.notifier).state = packageName;
  }

  Future<HarmonyAppDetail> _loadHarmonyDetail(String packageName) async {
    final detail = await ref
        .read(appManagementServiceProvider)
        .getHarmonyPackageDetailedInfo(widget.device.id, packageName);
    _harmonyDetails[_harmonyDetailKey(packageName)] = detail;
    return detail;
  }

  String _harmonyDetailKey(String packageName) =>
      '${widget.device.id}:$packageName';

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
    FocusScope.of(context).unfocus();
    _harmonyDetails.clear();
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
