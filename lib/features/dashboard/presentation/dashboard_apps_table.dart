part of 'dashboard_screen.dart';

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

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = _PackageTableWidths.adaptive(
          context: context,
          packages: widget.packages,
          viewportWidth: constraints.maxWidth,
        );
        final tableWidth = max(widths.total, constraints.maxWidth);

        return Scrollbar(
          controller: _horizontalController,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontalController,
            primary: false,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _PackageTableHeader(widths: widths),
                  Expanded(
                    child: Scrollbar(
                      controller: _verticalController,
                      child: ListView.builder(
                        controller: _verticalController,
                        primary: false,
                        itemCount: widget.packages.length,
                        itemBuilder: (context, index) {
                          final package = widget.packages[index];
                          return _PackageTableRow(
                            deviceId: widget.deviceId,
                            package: package,
                            selected: package.name == widget.selectedPackage,
                            widths: widths,
                            onSelected: () => widget.onSelected(package.name),
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
  const _PackageTableHeader({required this.widths});

  final _PackageTableWidths widths;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          _PackageHeaderCell(
            width: widths.appName,
            label: context.l10n.t('appName'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.packageName,
            label: context.l10n.t('packageName'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.version,
            label: context.l10n.t('version'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.minSdk,
            label: context.l10n.t('minSdkVersion'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.targetSdk,
            label: context.l10n.t('targetMaxSdk'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.storage,
            label: context.l10n.t('storageUsed'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.status,
            label: context.l10n.t('status'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.type,
            label: context.l10n.t('appType'),
            style: style,
          ),
          _PackageHeaderCell(
            width: widths.actions,
            label: context.l10n.t('actions'),
            style: style,
          ),
        ],
      ),
    );
  }
}

class _PackageHeaderCell extends StatelessWidget {
  const _PackageHeaderCell({
    required this.width,
    required this.label,
    required this.style,
  });

  final double width;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return _PackageCell(
      width: width,
      child: Text(
        label,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
  });

  final String deviceId;
  final AdbPackage package;
  final bool selected;
  final _PackageTableWidths widths;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: onSelected,
      onDoubleTap: () {
        onSelected();
        _showAppDetailsDialog(context, ref, deviceId, package);
      },
      child: Container(
        height: 72,
        color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
        child: Row(
          children: [
            _PackageCell(
              width: widths.appName,
              child: _AppNameCell(package: package),
            ),
            _PackageCell(
              width: widths.packageName,
              child: _TableText(package.name),
            ),
            _PackageCell(
              width: widths.version,
              child: _TableText(package.versionLabel),
            ),
            _PackageCell(
              width: widths.minSdk,
              child: Text(_sdkLabel(package.minSdk)),
            ),
            _PackageCell(
              width: widths.targetSdk,
              child: Text(_targetMaxSdkLabel(package)),
            ),
            _PackageCell(
              width: widths.storage,
              child: Text(package.storageLabel),
            ),
            _PackageCell(
              width: widths.status,
              child: _StatusChip(package: package),
            ),
            _PackageCell(
              width: widths.type,
              child: _AppTypeChip(package: package),
            ),
            _PackageCell(
              width: widths.actions,
              child: selected
                  ? _PackageActions(deviceId: deviceId, package: package)
                  : const SizedBox.shrink(),
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
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}

/// 应用名称单元格，附带轻量类型图标。
class _AppNameCell extends StatelessWidget {
  const _AppNameCell({required this.package});

  final AdbPackage package;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = package.flutter
        ? Icons.flutter_dash
        : package.system
        ? Icons.settings_applications
        : Icons.android;
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
          child: Tooltip(
            message: package.displayName,
            child: Text(
              package.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

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
    return CircleAvatar(
      radius: 14,
      backgroundColor: system
          ? colorScheme.surfaceContainerHighest
          : colorScheme.primaryContainer,
      child: Icon(
        icon,
        size: 18,
        color: system
            ? colorScheme.onSurfaceVariant
            : colorScheme.onPrimaryContainer,
      ),
    );
  }
}

/// 表格中的受限宽度文本，鼠标悬停时可查看完整值。
class _TableText extends StatelessWidget {
  const _TableText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: value,
      child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// 启用或停用状态徽标。
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.package});

  final AdbPackage package;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        package.enabled
            ? context.l10n.t('enabled')
            : context.l10n.t('disabled'),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// 展示系统/用户应用和 Flutter/native 分类。
class _AppTypeChip extends StatelessWidget {
  const _AppTypeChip({required this.package});

  final AdbPackage package;

  @override
  Widget build(BuildContext context) {
    final labels = [
      package.system ? context.l10n.t('systemApp') : context.l10n.t('userApp'),
      package.flutter
          ? context.l10n.t('flutterApp')
          : context.l10n.t('nativeApp'),
    ];
    return _TableText(labels.join(' / '));
  }
}

String _sdkLabel(int? value) => value == null ? '-' : '$value';

String _targetMaxSdkLabel(AdbPackage package) {
  final target = _sdkLabel(package.targetSdk);
  final max = _sdkLabel(package.maxSdk);
  return max == '-' ? target : '$target / $max';
}

/// 当前选中应用行的内联操作按钮。
