part of '../dashboard_screen.dart';

enum AppFilterType { user, system, all, favorites }

class AppsTab extends ConsumerStatefulWidget {
  const AppsTab({super.key, required this.device});

  final DiscoveredDevice device;

  @override
  ConsumerState<AppsTab> createState() => _AppsTabState();
}

/// 展示已安装应用，并提供包级操作。
class _AppsTabState extends ConsumerState<AppsTab> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  AppFilterType _appFilterType = AppFilterType.user;
  AppFilterType? _refreshingFilterType;
  PackageRefreshProgress? _refreshProgress;

  String get _refreshTooltip {
    final l10n = context.l10n;
    switch (_appFilterType) {
      case AppFilterType.user:
        return l10n.t('refreshUserPackages');
      case AppFilterType.system:
        return l10n.t('refreshSystemPackages');
      case AppFilterType.all:
        return l10n.t('refreshPackages');
      case AppFilterType.favorites:
        return l10n.t('refreshFavoritePackages');
    }
  }

  String _getRefreshTitle(AppFilterType type) {
    final l10n = context.l10n;
    switch (type) {
      case AppFilterType.user:
        return l10n.t('packageRefreshUserTitle');
      case AppFilterType.system:
        return l10n.t('packageRefreshSystemTitle');
      case AppFilterType.all:
        return l10n.t('packageRefreshTitle');
      case AppFilterType.favorites:
        return l10n.t('packageRefreshFavoriteTitle');
    }
  }
  String? _selectedPackage;
  bool _isGridView = false;
  bool _appContextMenuOpen = false;
  bool _runningAppAction = false;
  double _gridItemSize = 100.0;
  final Set<String> _refreshingPackageDetails = <String>{};
  final Set<String> _analyzingHarmonyPackages = <String>{};
  final Set<String> _clearingHarmonyCache = <String>{};
  final Map<String, HarmonyAppDetail> _harmonyDetails =
      <String, HarmonyAppDetail>{};
  final Set<String> _checkedPackages = <String>{};
  final ValueNotifier<_BatchProgressState?> _batchProgressNotifier =
      ValueNotifier<_BatchProgressState?>(null);

  /// 拆分后的布局和菜单通过 State 自身更新界面，避免访问 protected setState。
  void _updateAppView(VoidCallback update) => setState(update);

  void _toggleCheckPackage(String packageName) {
    setState(() {
      if (!_checkedPackages.add(packageName)) {
        _checkedPackages.remove(packageName);
      }
    });
  }

  void _toggleCheckAllPackages(List<AdbPackage> visible) {
    setState(() {
      final names = visible.map((p) => p.name).toSet();
      if (_checkedPackages.containsAll(names)) {
        _checkedPackages.removeAll(names);
      } else {
        _checkedPackages.addAll(names);
      }
    });
  }

  void _clearCheckedPackages() {
    if (_checkedPackages.isNotEmpty) {
      setState(() => _checkedPackages.clear());
    }
  }

  @override
  void dispose() {
    _filterController.dispose();
    _batchProgressNotifier.dispose();
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
  Widget build(BuildContext context) => _buildAppsTab(context);

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
      _openAppDetailsRoute(packageName);
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
        _closeAppDetails();
      }
      return;
    } finally {
      _analyzingHarmonyPackages.remove(packageName);
    }
    if (!mounted || widget.device.id != deviceId) return;
    _openAppDetailsRoute(packageName);
  }

  void _openAppDetailsRoute(String packageName) {
    ref.read(selectedAppPackageProvider.notifier).state = packageName;
    final target = GoRouter.of(context).namedLocation(
      AppRouteNames.appDetails,
      pathParameters: {
        'deviceId': widget.device.id,
        'packageName': packageName,
      },
    );
    if (GoRouterState.of(context).uri.toString() != target) {
      context.push(target);
    }
  }

  void _closeAppDetails() {
    ref.read(selectedAppPackageProvider.notifier).state = null;
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.goNamed(
      AppRouteNames.deviceTool,
      pathParameters: {'deviceId': widget.device.id, 'tool': 'apps'},
    );
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

  /// 按设备平台选择 HAP 或 APK，并调用对应的安装命令。
  Future<void> _installPackage() async {
    final isHarmony = widget.device.isHarmony;
    final group = XTypeGroup(
      label: isHarmony ? 'HAP' : 'APK',
      extensions: [isHarmony ? 'hap' : 'apk'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null || !mounted) {
      return;
    }
    final result = isHarmony
        ? await ref
            .read(hdcServiceProvider)
            .installApp(widget.device.id, file.path)
        : await ref
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

  /// 手动刷新应用时，按当前 Tab（用户/系统/全部/收藏）分批加载应用图标。
  Future<void> _refreshPackages() async {
    if (_refreshProgress != null) {
      return;
    }
    FocusScope.of(context).unfocus();
    _harmonyDetails.clear();
    _clearCheckedPackages();
    final filterType = _appFilterType;
    setState(() {
      _refreshingFilterType = filterType;
      _refreshProgress = const PackageRefreshProgress();
    });
    final notifier = ref.read(packagesProvider(widget.device.id).notifier);
    bool Function(AdbPackage)? filter;
    switch (filterType) {
      case AppFilterType.user:
        filter = (p) => !p.system;
        break;
      case AppFilterType.system:
        filter = (p) => p.system;
        break;
      case AppFilterType.all:
        filter = null;
        break;
      case AppFilterType.favorites:
        final favs = ref.read(appFavoritesProvider).value ?? const <String>{};
        filter = (p) => favs.contains(p.name);
        break;
    }
    try {
      await notifier.refreshAllPackagesWithIcons(
        onProgress: (progress) {
          if (mounted) {
            setState(() => _refreshProgress = progress);
          }
        },
        filter: filter,
      );
      if (mounted) {
        if (_refreshProgress?.stage != PackageRefreshStage.failed &&
            _refreshProgress?.failed == 0) {
          setState(() {
            _refreshProgress = null;
            _refreshingFilterType = null;
          });
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
