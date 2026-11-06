part of '../dashboard_screen.dart';

/// 设备列表相关的弹窗和状态色，集中在一处便于调整交互文案。
extension _DeviceListPanelActions on _DeviceListPanelState {
  /// 常用操作沿用既有截图、投屏与设备工具 Route，目标始终为右键设备。
  Future<void> _runDeviceContextAction(
    BuildContext context,
    DeviceContextAction action,
    RegisteredDevice device,
    AirPlaySessionData? airplaySession,
  ) async {
    switch (action) {
      case DeviceContextAction.screenshot:
        await _captureAndSaveDeviceScreenshot(
          context,
          ref,
          device.toDiscoveredDevice,
        );
      case DeviceContextAction.mirror:
        if (airplaySession != null) {
          await openAirPlayMirrorWindow(
            airplaySession,
            deviceId: device.id,
            deviceName: device.displayName,
          );
        } else {
          await openStandaloneMirrorWindow(
            context,
            ref,
            device.toDiscoveredDevice,
          );
        }
      case DeviceContextAction.edit:
        await _showEditDeviceInfoDialog(context, device);
      case DeviceContextAction.overview ||
          DeviceContextAction.apps ||
          DeviceContextAction.files ||
          DeviceContextAction.terminal:
        context.goNamed(
          AppRouteNames.deviceTool,
          pathParameters: {'deviceId': device.id, 'tool': action.toolSlug!},
        );
    }
  }

  Future<void> _deleteSelectedDevices(
    BuildContext context,
    int selectedCount,
  ) async {
    final allDevices = ref.read(deviceRegistryProvider);
    final hasUsbOnline = allDevices
        .where((d) => d.isChecked && d.isOnline && d.hasUsbConnection)
        .isNotEmpty;

    final String message;
    if (hasUsbOnline) {
      message = context.l10n
          .t('batchDeleteUsbWarning')
          .replaceAll('{count}', '$selectedCount');
    } else {
      message = context.l10n
          .t('deleteSelectedDevicesConfirm')
          .replaceAll('{count}', '$selectedCount');
    }

    final confirmed = await _confirm(context, message);
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


  /// 弹出统一设备信息编辑对话框（名称、标签标识、备注等）
  Future<void> _showEditDeviceInfoDialog(
    BuildContext context,
    RegisteredDevice device,
  ) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => DeviceInfoEditDialog(device: device),
    );
  }
}
