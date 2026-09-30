part of '../dashboard_screen.dart';

/// 单个应用数据行，单击进入应用详情，批量选择由 Checkbox 承担。
class _PackageTableRow extends StatelessWidget {
  const _PackageTableRow({
    required this.deviceId,
    required this.package,
    required this.selected,
    required this.checked,
    required this.widths,
    required this.onCheckChanged,
    required this.onOpened,
    required this.index,
  });

  final String deviceId;
  final AdbPackage package;
  final bool selected;
  final bool checked;
  final _PackageTableWidths widths;
  final ValueChanged<bool?> onCheckChanged;
  final VoidCallback onOpened;
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
          ],
        ),
      ),
    );
  }
}
