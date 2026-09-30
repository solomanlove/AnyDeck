part of '../dashboard_screen.dart';

class _PackageTable extends StatefulWidget {
  const _PackageTable({
    required this.deviceId,
    required this.packages,
    this.totalCount,
    required this.selectedPackage,
    required this.checkedPackages,
    required this.onToggleCheck,
    required this.onToggleCheckAll,
    required this.onOpened,
  });

  final String deviceId;
  final List<AdbPackage> packages;
  final int? totalCount;
  final String? selectedPackage;
  final Set<String> checkedPackages;
  final ValueChanged<String> onToggleCheck;
  final VoidCallback onToggleCheckAll;
  final ValueChanged<String> onOpened;

  @override
  State<_PackageTable> createState() => _PackageTableState();
}

class _PackageTableState extends State<_PackageTable> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  String _sortColumn = 'appName';
  bool _sortAscending = true;

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  void _toggleSort(String col) => setState(() {
    if (_sortColumn == col) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = col;
      _sortAscending = true;
    }
  });

  Widget _getSortIcon(String col) {
    if (_sortColumn != col) {
      return const Padding(
        padding: EdgeInsets.only(left: 4),
        child: Icon(
          CupertinoIcons.chevron_up_chevron_down,
          size: 14,
          color: Colors.grey,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(
        _sortAscending
            ? CupertinoIcons.chevron_up
            : CupertinoIcons.chevron_down,
        size: 14,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  List<AdbPackage> _sortedPackages() {
    final sortedList = List<AdbPackage>.from(widget.packages);
    sortedList.sort((a, b) {
      if (a.isLoaded && !b.isLoaded) {
        return -1;
      }
      if (!a.isLoaded && b.isLoaded) {
        return 1;
      }
      final cmp = switch (_sortColumn) {
        'appName' => a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        ),
        'packageName' => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        'version' => a.versionLabel.toLowerCase().compareTo(
          b.versionLabel.toLowerCase(),
        ),
        'minSdk' => (a.minSdk ?? 0).compareTo(b.minSdk ?? 0),
        'targetSdk' => (a.targetSdk ?? 0).compareTo(b.targetSdk ?? 0),
        'storage' => (a.storageBytes ?? 0).compareTo(b.storageBytes ?? 0),
        _ => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      };
      return _sortAscending ? cmp : -cmp;
    });
    return sortedList;
  }

  String _getFirstLetter(AdbPackage pkg) {
    final name = pkg.displayName.trim();
    if (name.isEmpty) return '#';
    final pinyin = PinyinHelper.getFirstWordPinyin(name).toUpperCase();
    if (pinyin.isNotEmpty && RegExp(r'[A-Z]').hasMatch(pinyin[0])) {
      return pinyin[0];
    }
    final firstChar = name[0].toUpperCase();
    if (RegExp(r'[A-Z]').hasMatch(firstChar)) {
      return firstChar;
    }
    return '#';
  }

  void _scrollToLetter(String letter, List<AdbPackage> sorted) {
    final targetIndex = sorted.indexWhere((p) => _getFirstLetter(p) == letter);
    if (targetIndex != -1 && _verticalController.hasClients) {
      // 每行高度 56，表头高度 48
      final offset = (targetIndex * 56.0).clamp(
        0.0,
        _verticalController.position.maxScrollExtent,
      );
      _verticalController.animateTo(
        offset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedPackages();
    final availableLetters = sorted.map(_getFirstLetter).toSet();

    return LayoutBuilder(
      builder: (context, constraints) {
        // 右侧为侧边栏预留 28 像素宽度
        final effectiveWidth = constraints.maxWidth - 28.0;
        final widths = _PackageTableWidths.adaptive(
          context: context,
          packages: sorted,
          viewportWidth: effectiveWidth,
          totalCount: widget.totalCount,
        );
        final tableWidth = max(widths.total, effectiveWidth);

        return Row(
          children: [
            Expanded(
              child: Scrollbar(
                controller: _horizontalController,
                notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  key: PageStorageKey<String>(
                    'apps-table-horizontal-${widget.deviceId}',
                  ),
                  controller: _horizontalController,
                  primary: false,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    height: constraints.maxHeight,
                    child: Column(
                      children: [
                        _PackageTableHeader(
                          widths: widths,
                          sortColumn: _sortColumn,
                          sortAscending: _sortAscending,
                          onSort: _toggleSort,
                          sortIconBuilder: _getSortIcon,
                          visibleCount: sorted.length,
                          totalCount: widget.totalCount,
                          isAllChecked: sorted.isNotEmpty &&
                              sorted.every((p) => widget.checkedPackages.contains(p.name)),
                          isIndeterminate: sorted.any((p) => widget.checkedPackages.contains(p.name)) &&
                              !sorted.every((p) => widget.checkedPackages.contains(p.name)),
                          onToggleCheckAll: widget.onToggleCheckAll,
                        ),
                        Expanded(
                          child: Scrollbar(
                            controller: _verticalController,
                            child: ListView.builder(
                              key: PageStorageKey<String>(
                                'apps-table-vertical-${widget.deviceId}',
                              ),
                              controller: _verticalController,
                              primary: false,
                              itemCount: sorted.length,
                              itemBuilder: (context, index) {
                                final package = sorted[index];
                                return _PackageTableRow(
                                  deviceId: widget.deviceId,
                                  package: package,
                                  selected: package.name == widget.selectedPackage,
                                  checked: widget.checkedPackages.contains(package.name),
                                  widths: widths,
                                  onCheckChanged: (_) => widget.onToggleCheck(package.name),
                                  onOpened: () => widget.onOpened(package.name),
                                  index: index,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AppsAlphabetSidebar(
                availableLetters: availableLetters,
                onLetterSelected: (letter) => _scrollToLetter(letter, sorted),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PackageTableHeader extends StatelessWidget {
  const _PackageTableHeader({
    required this.widths,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
    required this.sortIconBuilder,
    required this.isAllChecked,
    required this.isIndeterminate,
    required this.onToggleCheckAll,
    this.visibleCount,
    this.totalCount,
  });

  final _PackageTableWidths widths;
  final String sortColumn;
  final bool sortAscending;
  final ValueChanged<String> onSort;
  final Widget Function(String) sortIconBuilder;
  final bool isAllChecked;
  final bool isIndeterminate;
  final VoidCallback onToggleCheckAll;
  final int? visibleCount;
  final int? totalCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final appNameLabel = (visibleCount != null && totalCount != null)
        ? '${context.l10n.t('appName')} (${context.l10n.t('appCount').replaceAll('{visible}', '$visibleCount').replaceAll('{total}', '$totalCount')})'
        : context.l10n.t('appName');
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: widths.checkbox,
            child: Center(
              child: Checkbox(
                value: isIndeterminate ? null : isAllChecked,
                tristate: true,
                onChanged: (_) => onToggleCheckAll(),
              ),
            ),
          ),
          DashboardSortableHeaderCell(
            width: widths.appName,
            label: appNameLabel,
            style: style,
            sortIcon: sortIconBuilder('appName'),
            onTap: () => onSort('appName'),
          ),
          DashboardSortableHeaderCell(
            width: widths.version,
            label: context.l10n.t('version'),
            style: style,
            sortIcon: sortIconBuilder('version'),
            onTap: () => onSort('version'),
          ),
          DashboardSortableHeaderCell(
            width: widths.minSdk,
            label: context.l10n.t('minSdkVersion'),
            style: style,
            sortIcon: sortIconBuilder('minSdk'),
            onTap: () => onSort('minSdk'),
          ),
          DashboardSortableHeaderCell(
            width: widths.targetSdk,
            label: context.l10n.t('targetMaxSdk'),
            style: style,
            sortIcon: sortIconBuilder('targetSdk'),
            onTap: () => onSort('targetSdk'),
          ),
          DashboardSortableHeaderCell(
            width: widths.storage,
            label: context.l10n.t('storageUsed'),
            style: style,
            sortIcon: sortIconBuilder('storage'),
            onTap: () => onSort('storage'),
          ),
        ],
      ),
    );
  }
}

class _PackageCell extends StatelessWidget {
  const _PackageCell({required this.width, required this.child});

  static const horizontalPadding = 24.0;

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}

/// 展示应用名称和包名，并且呈现圆角矩形的应用图标（类似 ListTile 结构），支持点击收藏（✨）。
class _AppNameCell extends ConsumerWidget {
  const _AppNameCell({required this.deviceId, required this.package});

  final String deviceId;
  final AdbPackage package;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 28,
            height: 28,
            child: _PackageIcon(deviceId: deviceId, package: package),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Tooltip(
                      message: package.displayName,
                      child: Text(
                        package.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Consumer(
                    builder: (context, ref, _) {
                      final favorites = ref.watch(appFavoritesProvider).value ?? const <String>{};
                      final isFav = favorites.contains(package.name);
                      return InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => ref.read(appFavoritesProvider.notifier).toggle(package.name),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Icon(
                            isFav ? CupertinoIcons.star_fill : CupertinoIcons.star,
                            size: 14,
                            color: isFav ? const Color(0xfff5a623) : colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                          ),
                        ),
                      );
                    },
                  ),
                  if (package.debuggable) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: colorScheme.error.withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        'DEBUG',
                        style: TextStyle(
                          color: colorScheme.onErrorContainer,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Tooltip(
                message: package.name,
                child: Text(
                  package.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TableText extends StatelessWidget {
  const _TableText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: value,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

String _sdkLabel(int? value) => value == null ? '-' : '$value';

String _targetMaxSdkLabel(AdbPackage package) {
  final target = _sdkLabel(package.targetSdk);
  final max = _sdkLabel(package.maxSdk);
  return max == '-' ? target : '$target / $max';
}

/// 当前选中应用的操作按钮。
