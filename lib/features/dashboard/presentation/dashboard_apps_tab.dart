part of 'dashboard_screen.dart';

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
                    prefixIcon: const Icon(Icons.search),
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
                icon: const Icon(Icons.install_desktop),
                label: Text(context.l10n.t('installApk')),
                onPressed: _installApk,
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: context.l10n.t('refreshPackages'),
                icon: const Icon(Icons.refresh),
                onPressed: _refreshingPackages ? null : _refreshPackages,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: packages.when(
              loading: () => _PanelMessage(
                icon: Icons.sync,
                title: context.l10n.t('loadingPackages'),
              ),
              error: (error, stackTrace) => _PanelMessage(
                icon: Icons.error_outline,
                title: context.l10n.t('packageListFailed'),
                subtitle: error.toString(),
              ),
              data: (items) {
                final filtered = _filterPackages(items);
                if (filtered.isEmpty) {
                  return _PanelMessage(
                    icon: Icons.apps_outlined,
                    title: context.l10n.t('noPackages'),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.l10n
                          .t('appCount')
                          .replaceAll('{visible}', '${filtered.length}')
                          .replaceAll('{total}', '${items.length}'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _PackageTable(
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
}

/// 桌面风格的应用表格，包含元数据列和行操作。
