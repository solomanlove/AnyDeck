part of '../dashboard_screen.dart';

class _PackageTable extends StatefulWidget {
  const _PackageTable({
    required this.deviceId,
    required this.packages,
    required this.selectedPackage,
    required this.onSelected,
  });

  final String deviceId;
  final List<AdbPackage> packages;
  final String? selectedPackage;
  final ValueChanged<String> onSelected;

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

  int _compareAppType(AdbPackage a, AdbPackage b) {
    final systemCmp = (a.system ? 1 : 0).compareTo(b.system ? 1 : 0);
    return systemCmp != 0
        ? systemCmp
        : (a.flutter ? 1 : 0).compareTo(b.flutter ? 1 : 0);
  }

  List<AdbPackage> _sortedPackages() {
    final sortedList = List<AdbPackage>.from(widget.packages);
    sortedList.sort((a, b) {
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
        'status' => (a.enabled ? 1 : 0).compareTo(b.enabled ? 1 : 0),
        'type' => _compareAppType(a, b),
        _ => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      };
      return _sortAscending ? cmp : -cmp;
    });
    return sortedList;
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedPackages();
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = _PackageTableWidths.adaptive(
          context: context,
          packages: sorted,
          viewportWidth: constraints.maxWidth,
        );
        final tableWidth = max(widths.total, constraints.maxWidth);

        return Scrollbar(
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
                            widths: widths,
                            onSelected: () => widget.onSelected(package.name),
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
  });

  final _PackageTableWidths widths;
  final String sortColumn;
  final bool sortAscending;
  final ValueChanged<String> onSort;
  final Widget Function(String) sortIconBuilder;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
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
          DashboardSortableHeaderCell(
            width: widths.appName,
            label: context.l10n.t('appName'),
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
          DashboardSortableHeaderCell(
            width: widths.status,
            label: context.l10n.t('status'),
            style: style,
            sortIcon: sortIconBuilder('status'),
            onTap: () => onSort('status'),
          ),
          DashboardSortableHeaderCell(
            width: widths.type,
            label: context.l10n.t('appType'),
            style: style,
            sortIcon: sortIconBuilder('type'),
            onTap: () => onSort('type'),
          ),
        ],
      ),
    );
  }
}

/// 单个应用数据行。
class _PackageTableRow extends ConsumerWidget {
  const _PackageTableRow({
    required this.deviceId,
    required this.package,
    required this.selected,
    required this.widths,
    required this.onSelected,
    required this.index,
  });

  final String deviceId;
  final AdbPackage package;
  final bool selected;
  final _PackageTableWidths widths;
  final VoidCallback onSelected;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color? rowColor = selected
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
        : index % 2 == 0
        ? null
        : Theme.of(
            context,
          ).colorScheme.surfaceContainerLowest.withValues(alpha: 0.5);

    return InkWell(
      onTap: onSelected,
      onDoubleTap: () {
        onSelected();
        _showAppDetailsDialog(context, ref, deviceId, package);
      },
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: rowColor,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            _PackageCell(
              width: widths.appName,
              child: _AppNameCell(package: package),
            ),
            _PackageCell(
              width: widths.version,
              child: _TableText(package.versionLabel),
            ),
            _PackageCell(
              width: widths.minSdk,
              child: Text(
                _sdkLabel(package.minSdk),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            _PackageCell(
              width: widths.targetSdk,
              child: Text(
                _targetMaxSdkLabel(package),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            _PackageCell(
              width: widths.storage,
              child: Text(
                package.storageLabel,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            _PackageCell(
              width: widths.status,
              child: Chip(
                label: Text(
                  package.enabled
                      ? context.l10n.t('enabled')
                      : context.l10n.t('disabled'),
                  style: const TextStyle(fontSize: 12),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
            _PackageCell(
              width: widths.type,
              child: _TableText(
                '${package.system ? context.l10n.t('systemApp') : context.l10n.t('userApp')} / ${package.flutter ? context.l10n.t('flutterApp') : context.l10n.t('nativeApp')}',
              ),
            ),
          ],
        ),
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

/// 展示应用名称和包名，并且呈现圆角矩形的应用图标（类似 ListTile 结构）
class _AppNameCell extends StatelessWidget {
  const _AppNameCell({required this.package});

  final AdbPackage package;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = package.flutter
        ? CupertinoIcons.square_grid_2x2
        : package.system
        ? CupertinoIcons.settings
        : CupertinoIcons.device_phone_portrait;
    final iconPath = package.iconLocalPath;

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 28,
            height: 28,
            child: iconPath != null && File(iconPath).existsSync()
                ? Image.file(
                    File(iconPath),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        _FallbackAppIcon(
                          icon: icon,
                          system: package.system,
                          colorScheme: colorScheme,
                        ),
                  )
                : _FallbackAppIcon(
                    icon: icon,
                    system: package.system,
                    colorScheme: colorScheme,
                  ),
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

/// 默认的圆角矩形应用占位图标
class _FallbackAppIcon extends StatelessWidget {
  const _FallbackAppIcon({
    required this.icon,
    required this.system,
    required this.colorScheme,
  });
  final IconData icon;
  final bool system;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: system
            ? colorScheme.surfaceContainerHighest
            : colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Icon(
          icon,
          size: 16,
          color: system
              ? colorScheme.onSurfaceVariant
              : colorScheme.onPrimaryContainer,
        ),
      ),
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
