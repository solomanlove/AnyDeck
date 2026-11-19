part of '../dashboard_screen.dart';

/// 满宽居左的中性色批量工具栏；筛选保留隐藏勾选，数量说明收入口 Tooltip。
extension _DeviceSelectionBar on _DeviceListPanelState {
  Widget _buildSelectionBar(
    BuildContext context,
    List<RegisteredDevice> visible,
    List<RegisteredDevice> checked,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = visible.where((device) => device.isChecked).length;
    final all = visible.isNotEmpty && count == visible.length;
    final hidden = checked.length - count;
    final online = checked.where((d) => d.isOnline).toList();
    final android = online.where((d) => !d.isIos && !d.isHarmony).toList();
    final selectionHint = [
      context.l10n.t('deviceWorkspaceAllResults'),
      context.l10n
          .t('deviceWorkspaceSelected')
          .replaceAll('{count}', '${checked.length}'),
      if (hidden > 0)
        context.l10n
            .t('deviceWorkspaceHiddenSelected')
            .replaceAll('{count}', '$hidden'),
    ].join('\n');
    return Container(
      key: const Key('deviceBatchActions'),
      width: double.infinity,
      alignment: Alignment.centerLeft,
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.appColors.subtleSurface,
        borderRadius: AppThemeSizes.radiusLarge,
      ),
      // 窄窗口横向滚动，始终按固定顺序展示同一行操作。
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Tooltip(
              message: selectionHint,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 24,
                    child: Checkbox(
                      key: const Key('deviceSelectAll'),
                      activeColor: scheme.onSurface,
                      checkColor: scheme.surface,
                      side: theme.deviceSelectionCheckboxSide,
                      overlayColor: WidgetStatePropertyAll(
                        theme.appColors.hoverSurface,
                      ),
                      tristate: true,
                      value: count > 0 && !all ? null : all,
                      onChanged: visible.isEmpty
                          ? null
                          : (_) {
                              final registry = ref.read(
                                deviceRegistryProvider.notifier,
                              );
                              for (final device in visible) {
                                if (device.isChecked == all) {
                                  registry.toggleCheck(device.id);
                                }
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n
                        .t('deviceWorkspaceSelectAll')
                        .replaceAll('{count}', '${checked.length}'),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            for (final item in [
              ('mirror', 'batchMirror', online.isNotEmpty),
              (
                'screenshot',
                'deviceWorkspaceBatchScreenshot',
                android.isNotEmpty,
              ),
              ('record', 'screenRecord', android.isNotEmpty),
              ('install', 'deviceWorkspaceBatchInstall', android.isNotEmpty),
              ('push', 'batchPush', android.isNotEmpty),
              ('script', 'batchScript', online.any((device) => !device.isIos)),
              ('schedule', 'deviceWorkspaceBatchSchedule', android.isNotEmpty),
              ('delete', 'deviceWorkspaceBatchDelete', checked.isNotEmpty),
            ])
              TextButton(
                key: Key('deviceBatch-${item.$1}'),
                onPressed: item.$3 && !_batchActionRunning
                    ? () => _executeWorkspaceBatch(
                        context,
                        item.$1,
                        checked,
                        online,
                        android,
                      )
                    : null,
                style: TextButton.styleFrom(
                  foregroundColor: item.$1 == 'delete'
                      ? scheme.error
                      : scheme.onSurface,
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
                ),
                child: Text(context.l10n.t(item.$2)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeWorkspaceBatch(
    BuildContext context,
    String action,
    List<RegisteredDevice> checked,
    List<RegisteredDevice> online,
    List<RegisteredDevice> android,
  ) async {
    if (_batchActionRunning) return;
    _setBatchActionRunning(true);
    try {
      switch (action) {
        case 'mirror':
          await _handleBatchMirror(context, online);
        case 'screenshot':
          await _handleBatchScreenshot(context, android);
        case 'record':
          await _handleBatchRecord(context, android);
        case 'install':
          await _handleBatchInstall(context, android);
        case 'push':
          await _handleBatchPush(context, android);
        case 'script':
          // Android/HarmonyOS 分别由原有脚本执行器路由到 ADB/HDC。
          await _handleBatchScript(
            context,
            online.where((device) => !device.isIos).toList(),
          );
        case 'schedule':
          await _handleBatchSchedule(context, android);
        case 'delete':
          await _deleteSelectedDevices(context, checked.length);
      }
    } finally {
      _setBatchActionRunning(false);
    }
  }
}
