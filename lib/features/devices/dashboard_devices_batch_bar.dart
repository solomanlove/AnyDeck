part of '../dashboard_screen.dart';

/// 批量管理独立工具栏；筛选只改变可见集合，不偷偷清除隐藏设备的勾选。
extension _DeviceSelectionBar on _DeviceListPanelState {
  Widget _buildSelectionBar(
    BuildContext context,
    List<RegisteredDevice> visible,
    List<RegisteredDevice> checked,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final count = visible.where((device) => device.isChecked).length;
    final all = visible.isNotEmpty && count == visible.length;
    final hidden = checked.length - count;
    final online = checked.where((d) => d.isOnline).toList();
    final android = online.where((d) => !d.isIos && !d.isHarmony).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: AppThemeSizes.radiusLarge,
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 24,
                child: Checkbox(
                  key: const Key('deviceSelectAll'),
                  tristate: true,
                  value: count > 0 && !all ? null : all,
                  onChanged: visible.isEmpty
                      ? null
                      : (_) {
                          final registry = ref.read(
                            deviceRegistryProvider.notifier,
                          );
                          for (final device in visible) {
                            if (device.isChecked == all)
                              registry.toggleCheck(device.id);
                          }
                        },
                ),
              ),
              const SizedBox(width: 6),
              Text(context.l10n.t('deviceWorkspaceAllResults')),
            ],
          ),
          Text(
            context.l10n
                .t('deviceWorkspaceSelected')
                .replaceAll('{count}', '${checked.length}'),
          ),
          if (hidden > 0)
            Text(
              context.l10n
                  .t('deviceWorkspaceHiddenSelected')
                  .replaceAll('{count}', '$hidden'),
            ),
          TextButton(
            onPressed: checked.isEmpty
                ? null
                : () {
                    final registry = ref.read(deviceRegistryProvider.notifier);
                    for (final device in checked) {
                      registry.toggleCheck(device.id);
                    }
                  },
            child: Text(context.l10n.t('deviceWorkspaceClearSelection')),
          ),
          PopupMenuButton<String>(
            key: const Key('deviceBatchActions'),
            enabled: checked.isNotEmpty,
            tooltip: context.l10n.t('deviceWorkspaceBatchActions'),
            onSelected: (action) => _executeWorkspaceBatch(
              context,
              action,
              checked,
              online,
              android,
            ),
            itemBuilder: (_) => [
              for (final item in [
                ('mirror', 'batchMirror', online.isNotEmpty),
                ('screenshot', 'batchScreenshot', android.isNotEmpty),
                ('record', 'batchRecord', android.isNotEmpty),
                ('install', 'batchInstall', android.isNotEmpty),
                ('push', 'batchPush', android.isNotEmpty),
                ('script', 'batchScript', android.isNotEmpty),
                ('schedule', 'batchSchedule', android.isNotEmpty),
                ('delete', 'deleteSelectedDevices', true),
              ])
                PopupMenuItem(
                  value: item.$1,
                  enabled: item.$3,
                  child: Text(context.l10n.t(item.$2)),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.t('deviceWorkspaceBatchActions'),
                    style: TextStyle(
                      color: checked.isEmpty
                          ? Theme.of(context).disabledColor
                          : scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.keyboard_arrow_down, size: 16),
                ],
              ),
            ),
          ),
        ],
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
        await _handleBatchScript(context, android);
      case 'schedule':
        await _handleBatchSchedule(context, android);
      case 'delete':
        await _deleteSelectedDevices(context, checked.length);
    }
  }
}
