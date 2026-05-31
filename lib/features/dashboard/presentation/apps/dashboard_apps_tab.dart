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

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(packagesProvider(widget.device.id));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filterController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(CupertinoIcons.search),
                    labelText: context.l10n.t('filterPackage'),
                  ),
                  onChanged: (value) => setState(() => _filter = value),
                ),
              ),
              const SizedBox(width: 8),
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
              FilledButton.icon(
                icon: const Icon(CupertinoIcons.square_arrow_down),
                label: Text(context.l10n.t('installApk')),
                onPressed: _installApk,
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: context.l10n.t('refreshPackages'),
                icon: const Icon(CupertinoIcons.refresh),
                onPressed: _refreshingPackages ? null : _refreshPackages,
              ),
              const SizedBox(width: 8),
              _buildToolbarButton(
                icon: CupertinoIcons.zoom_in,
                onPressed: (_isGridView && _gridItemSize < 160.0)
                    ? () => setState(() => _gridItemSize = min(160.0, _gridItemSize + 15.0))
                    : null,
                active: false,
                tooltip: context.l10n.t('zoomIn'),
              ),
              _buildToolbarButton(
                icon: CupertinoIcons.zoom_out,
                onPressed: (_isGridView && _gridItemSize > 70.0)
                    ? () => setState(() => _gridItemSize = max(70.0, _gridItemSize - 15.0))
                    : null,
                active: false,
                tooltip: context.l10n.t('zoomOut'),
              ),
              _buildDivider(),
              _buildToolbarButton(
                icon: CupertinoIcons.square_grid_2x2,
                onPressed: () => setState(() => _isGridView = true),
                active: _isGridView,
                tooltip: context.l10n.t('gridView'),
              ),
              _buildToolbarButton(
                icon: CupertinoIcons.list_bullet,
                onPressed: () => setState(() => _isGridView = false),
                active: !_isGridView,
                tooltip: context.l10n.t('listView'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: packages.when(
              loading: () => _PanelMessage(
                icon: CupertinoIcons.arrow_2_circlepath,
                title: context.l10n.t('loadingPackages'),
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
                              onSelected: (packageName) =>
                                  setState(() => _selectedPackage = packageName),
                              gridItemSize: _gridItemSize,
                            )
                          : _PackageTable(
                              deviceId: widget.device.id,
                              packages: filtered,
                              selectedPackage: _selectedPackage,
                              onSelected: (packageName) =>
                                  setState(() => _selectedPackage = packageName),
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

  /// 手动刷新时强制读取手机数据，并覆盖本地应用列表缓存。
  Future<void> _refreshPackages() async {
    if (_refreshingPackages) {
      return;
    }
    setState(() => _refreshingPackages = true);
    try {
      await ref
          .read(appManagementServiceProvider)
          .refreshPackages(widget.device.id);
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

  Widget _buildToolbarButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required bool active,
    required String tooltip,
  }) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
          border: Border.all(
            color: active
                ? theme.colorScheme.outline.withValues(alpha: 0.3)
                : Colors.transparent,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: IconButton(
          icon: Icon(icon, size: 20),
          onPressed: onPressed,
          style: IconButton.styleFrom(
            minimumSize: const Size(36, 36),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        height: 20,
        width: 1,
        child: VerticalDivider(
          color: theme.dividerColor.withValues(alpha: 0.6),
          width: 1,
          thickness: 1,
        ),
      ),
    );
  }
}

/// 桌面风格的应用表格，包含元数据列和行操作。
