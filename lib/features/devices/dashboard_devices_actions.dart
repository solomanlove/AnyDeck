part of '../dashboard_screen.dart';

/// 设备列表相关的弹窗和状态色，集中在一处便于调整交互文案。
extension _DeviceListPanelActions on _DeviceListPanelState {
  /// 仅订阅对应 AVD，其他模拟器启动时无需刷新当前操作按钮。
  EmulatorLaunchState? _watchWorkspaceEmulatorLaunch(
    BuildContext context,
    WidgetRef actionRef,
    RegisteredDevice device,
  ) {
    final name = device.emulatorAvdName;
    if (device.isOnline || !device.emulatorAvdConfirmed || name == null) {
      return null;
    }
    final launch = emulatorLaunchProvider.select((states) => states[name]);
    actionRef.listen(launch, (previous, next) {
      if (next != null &&
          next.errorKey != null &&
          next.errorKey != previous?.errorKey) {
        _showSnack(context, _emulatorErrorSummary(context, next), isError: true);
      }
    });
    return actionRef.watch(launch);
  }

  /// 列表与设备墙使用相同的启动状态和按钮文案。
  (String, IconData) _workspaceActionAppearance(
    RegisteredDevice device,
    EmulatorLaunchState? launch,
  ) {
    if (device.isOnline) return ('screenMirror', Icons.ondemand_video_outlined);
    if (!device.id.startsWith('emulator-')) {
      return ('deviceWorkspaceReconnect', Icons.link);
    }
    if (launch?.starting == true) return ('emulatorStarting', Icons.play_arrow);
    if (launch?.processAlive == true) return ('emulatorAdbHelp', Icons.link_off);
    return ('deviceWorkspaceStartEmulator', Icons.play_arrow);
  }

  /// 校验当前连接，避免把 ADB 离线、未授权或身份仍待确认的实例再启动一次。
  Future<void> _startWorkspaceEmulator(
    BuildContext context,
    RegisteredDevice device,
  ) async {
    final name = device.emulatorAvdName;
    if (!device.emulatorAvdConfirmed || name == null) {
      context.goNamed(AppRouteNames.emulators);
      return;
    }
    if (ref.read(emulatorLaunchProvider)[name]?.starting == true) return;

    final connections = await ref.read(emulatorConnectionsProvider.future);
    if (!context.mounted) return;
    final connection = connections[name];
    if (connection?.isOnline == true) return;
    final launch = ref.read(emulatorLaunchProvider)[name];
    if (launch?.starting == true) return;

    // 端口可能已被另一 AVD 复用。只在仍无法确认该端口归属时保守拦截。
    final unresolvedTransport =
        connection == null &&
            EmulatorConnectionService.isTransport(device.id) &&
            !connections.values.any((item) => item.id == device.id)
        ? ref
              .read(discoveredDevicesProvider)
              .value
              ?.where(
                (item) => item.id == device.id && !item.isHarmony && !item.isIos,
              )
              .firstOrNull
        : null;
    final status = connection?.status ?? unresolvedTransport?.status;
    if (status != null || launch?.processAlive == true) {
      final diagnostic = switch (status) {
        'unauthorized' => const EmulatorLaunchState(
          processAlive: true,
          errorKey: 'emulatorAdbUnauthorized',
        ),
        'offline' => const EmulatorLaunchState(
          processAlive: true,
          errorKey: 'emulatorAdbOffline',
        ),
        _ => launch?.errorKey != null && launch?.processAlive == true
            ? launch!
            : const EmulatorLaunchState(
                processAlive: true,
                errorKey: 'emulatorLaunchTimeout',
              ),
      };
      await _showEmulatorError(context, diagnostic);
      return;
    }
    await ref.read(emulatorLaunchProvider.notifier).launch(name);
  }

  /// 常用操作沿用既有截图、投屏与设备工具 Route，目标始终为右键设备。
  Future<void> _runDeviceContextAction(
    BuildContext context,
    DeviceContextAction action,
    RegisteredDevice device,
    AirPlaySessionData? airplaySession,
  ) async {
    switch (action) {
      case DeviceContextAction.preview:
        await ref.read(deviceScreenPreviewProvider(device.id).notifier).capture();
        if (!context.mounted) return;
        final preview = ref.read(deviceScreenPreviewProvider(device.id));
        if (preview.hasError) {
          _showSnack(context,
            '${context.l10n.t('error')}: ${preview.error}', isError: true);
        }
      case DeviceContextAction.share:
        await showDialog<void>(context: context,
          builder: (_) => DeviceShareDialog(device: device));
      case DeviceContextAction.wireless:
        await _runAdbAction(context, ref, ref.read(deviceRegistryProvider.notifier)
            .connectPreferredAdbWireless(device));
      case DeviceContextAction.disconnect:
        for (final id in device.connections.where((id) =>
            id.contains(':') || id.contains('.'))) {
          await _runAdbAction(context, ref,
            ref.read(deviceRegistryProvider.notifier).disconnectNetworkDevice(id));
          if (!context.mounted) return;
        }
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
