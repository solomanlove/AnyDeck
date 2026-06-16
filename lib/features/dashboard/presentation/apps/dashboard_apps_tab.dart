part of '../dashboard_screen.dart';

class _AppsTab extends ConsumerStatefulWidget {
  const _AppsTab({required this.device});

  final AdbDevice device;

  @override
  ConsumerState<_AppsTab> createState() => _AppsTabState();
}

/// 展示已安装应用，并提供包级操作。
class _AppsTabState extends ConsumerState<_AppsTab> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  bool _hideSystemApps = true;
  bool _refreshingPackages = false;
  String? _selectedPackage;
  bool _isGridView = false;
  double _gridItemSize = 100.0;

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
    final renderBox = _textFieldKey.currentContext?.findRenderObject() as RenderBox?;
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
        constraints: const BoxConstraints(
          maxHeight: 300,
        ),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
            if (history.isNotEmpty) ...[
              Divider(
                height: 1,
                color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.l10n.t('searchHistory'),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        ref.read(appsSearchHistoryProvider.notifier).clear();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.clock,
                              size: 14,
                              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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
                                ref.read(appsSearchHistoryProvider.notifier).remove(item);
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              splashRadius: 16,
                              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (!isOnline)
            _buildOfflineWarningBanner(
              context,
              context.l10n.t('offlineAppsWarning'),
            ),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  key: _textFieldKey,
                  height: 38,
                  child: TapRegion(
                    groupId: 'apps_search_filter_region',
                    child: CompositedTransformTarget(
                      link: _filterLayerLink,
                      child: TextField(
                        controller: _filterController,
                        focusNode: _filterFocusNode,
                        onChanged: (value) => setState(() => _filter = value),
                        onSubmitted: (value) {
                          final val = value.trim();
                          if (val.isNotEmpty) {
                            ref.read(appsSearchHistoryProvider.notifier).add(val);
                          }
                          _hideFilterOverlay();
                        },
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
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _hideSystemApps,
                    onChanged: (value) =>
                        setState(() => _hideSystemApps = value ?? true),
                  ),
                  Text(context.l10n.t('hideSystemApps')),
                ],
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: context.l10n.t('refreshPackages'),
                icon: const Icon(CupertinoIcons.refresh, size: 20),
                onPressed: (isOnline && !_refreshingPackages)
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
                selectedIcon: const Icon(
                  CupertinoIcons.list_bullet,
                  size: 20,
                ),
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
          const SizedBox(height: 12),
          Expanded(
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
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n
                                .t('appCount')
                                .replaceAll('{visible}', '${filtered.length}')
                                .replaceAll('{total}', '${items.length}'),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        if (selectedPackage != null)
                          _PackageActions(
                            deviceId: widget.device.id,
                            package: selectedPackage,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _isGridView
                          ? _PackageGrid(
                              deviceId: widget.device.id,
                              packages: filtered,
                              selectedPackage: _selectedPackage,
                              onSelected: (packageName) => setState(
                                () => _selectedPackage = packageName,
                              ),
                              gridItemSize: _gridItemSize,
                            )
                          : _PackageTable(
                              deviceId: widget.device.id,
                              packages: filtered,
                              selectedPackage: _selectedPackage,
                              onSelected: (packageName) => setState(
                                () => _selectedPackage = packageName,
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 对应用名和包名执行大小写不敏感筛选，并且支持拼音匹配（全拼、首字母），可隐藏系统应用。
  List<AdbPackage> _filterPackages(List<AdbPackage> items) {
    final filter = _filter.trim().toLowerCase();
    final cleanFilter = filter.replaceAll(' ', '');
    return items
        .where((package) => !_hideSystemApps || !package.system)
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

  /// 手动刷新时清空本地缓存，并触发重新渐进式提取应用列表。
  Future<void> _refreshPackages() async {
    if (_refreshingPackages) {
      return;
    }
    setState(() => _refreshingPackages = true);
    try {
      final service = ref.read(appManagementServiceProvider);
      await service.clearPackageCache(widget.device.id);
      ref.invalidate(packagesProvider(widget.device.id));
    } catch (error) {
      if (mounted) {
        _showSnack(context, error.toString(), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _refreshingPackages = false);
      }
    }
  }

}

/// 桌面风格的应用表格，包含元数据列和行操作。
