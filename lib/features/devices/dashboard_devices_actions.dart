part of '../dashboard_screen.dart';

/// 设备列表相关的弹窗和状态色，集中在一处便于调整交互文案。
extension _DeviceListPanelActions on _DeviceListPanelState {
  Future<void> _deleteSelectedDevices(
    BuildContext context,
    int selectedCount,
  ) async {
    final confirmed = await _confirm(
      context,
      context.l10n
          .t('deleteSelectedDevicesConfirm')
          .replaceAll('{count}', '$selectedCount'),
    );
    if (!context.mounted || !confirmed) {
      return;
    }

    await ref.read(deviceRegistryProvider.notifier).removeCheckedDevices();
    if (!context.mounted) {
      return;
    }

    _showSnack(
      context,
      context.l10n
          .t('selectedDevicesDeleted')
          .replaceAll('{count}', '$selectedCount'),
    );
  }

  Color _getStatusBgColor(String status) {
    return switch (status) {
      'device' => const Color(0xFFE8F5E9),
      'unauthorized' => const Color(0xFFFFF3E0),
      'offline' => const Color(0xFFF5F5F5),
      _ => const Color(0xFFF5F5F5),
    };
  }

  Color _getStatusTextColor(String status) {
    return switch (status) {
      'device' => const Color(0xFF2E7D32),
      'unauthorized' => const Color(0xFFE65100),
      'offline' => const Color(0xFF9E9E9E),
      _ => const Color(0xFF9E9E9E),
    };
  }

  String _getStatusText(BuildContext context, String status) {
    return switch (status) {
      'device' => context.l10n.t('deviceOnline'),
      'unauthorized' => context.l10n.t('deviceUnauthorized'),
      'offline' => context.l10n.t('deviceOffline'),
      _ => status,
    };
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    RegisteredDevice device,
  ) async {
    final controller = TextEditingController(
      text: device.customName ?? device.model ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.t('editDeviceName')),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: context.l10n.t('enterDeviceName'),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: Text(context.l10n.t('confirm')),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (name != null && context.mounted) {
      await ref.read(deviceRegistryProvider.notifier).setAlias(device.id, name);
    }
  }
}
