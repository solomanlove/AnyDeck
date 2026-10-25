part of '../dashboard_screen.dart';

/// 表格单元格文本，溢出时保留完整内容供悬停查看。
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

/// 单个应用数据行，单击进入应用详情，批量选择由 Checkbox 承担。
class _PackageTableRow extends StatelessWidget {
  const _PackageTableRow({
    required this.deviceId,
    required this.isHarmony,
    required this.package,
    required this.selected,
    required this.checked,
    required this.widths,
    required this.onCheckChanged,
    required this.onOpened,
    required this.onContextMenuRequested,
    required this.index,
  });

  final String deviceId;
  final bool isHarmony;
  final AdbPackage package;
  final bool selected;
  final bool checked;
  final _PackageTableWidths widths;
  final ValueChanged<bool?> onCheckChanged;
  final VoidCallback onOpened;
  final ValueChanged<Offset> onContextMenuRequested;
  final int index;

  @override
  Widget build(BuildContext context) {
    final Color? rowColor = selected || checked
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: checked ? 0.25 : 0.4)
        : index % 2 == 0
        ? null
        : Theme.of(
            context,
          ).colorScheme.surfaceContainerLowest.withValues(alpha: 0.5);

    return InkWell(
      onTap: onOpened,
      onSecondaryTapDown: isHarmony
          ? (details) => onContextMenuRequested(details.globalPosition)
          : null,
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
            SizedBox(
              width: widths.checkbox,
              child: Center(
                child: Checkbox(
                  value: checked,
                  onChanged: onCheckChanged,
                ),
              ),
            ),
            _PackageCell(
              width: widths.appName,
              child: _AppNameCell(deviceId: deviceId, package: package),
            ),
            _PackageCell(
              width: widths.version,
              child: _TableText(package.versionLabel),
            ),
            if (!isHarmony)
              _PackageCell(
                width: widths.minSdk,
                child: Text(
                  _sdkLabel(package.minSdk),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            if (isHarmony)
              _PackageCell(
                width: widths.installTime,
                child: _TableText(_formatDetailTime(package.firstInstallTime)),
              ),
            _PackageCell(
              width: widths.targetSdk,
              child: Text(
                isHarmony ? _sdkLabel(package.targetSdk) : _targetMaxSdkLabel(package),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            _PackageCell(
              width: widths.storage,
              child: Text(
                package.storagePermissionDenied
                    ? context.l10n.t('storagePermissionDenied')
                    : package.storageLabel,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
