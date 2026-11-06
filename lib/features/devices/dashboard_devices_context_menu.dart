part of '../dashboard_screen.dart';

/// 设备列表右键入口：复用平台能力策略，执行前重新解析当前设备快照。
extension _DeviceListContextMenu on _DeviceListPanelState {
  Future<void> _showDeviceContextMenu(
    BuildContext context,
    RegisteredDevice device,
    Offset position, {
    AirPlaySessionData? airplaySession,
  }) async {
    if (_deviceContextMenuOpen || _deviceQuickActionRunning) return;
    _selectContextDevice(device.id);
    final overlayState = Navigator.of(context, rootNavigator: true).overlay;
    final overlay = overlayState?.context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final localPosition = overlay.globalToLocal(position);
    final theme = Theme.of(context);
    _deviceContextMenuOpen = true;
    try {
      final action = await showMenu<DeviceContextAction>(
        context: context,
        useRootNavigator: true,
        position: RelativeRect.fromSize(
          localPosition & Size.zero,
          overlay.size,
        ),
        color: theme.colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: AppThemeSizes.radiusLarge,
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        items: [
          for (final action in DeviceContextAction.values)
            if (action.isVisibleFor(device))
              PopupMenuItem<DeviceContextAction>(
                value: action,
                enabled: action.isEnabledFor(
                  device,
                  hasAirPlaySession: airplaySession != null,
                ),
                height: 38,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_deviceContextActionIcon(action), size: 16),
                    const SizedBox(width: 8),
                    Flexible(child: Text(context.l10n.t(action.labelKey))),
                  ],
                ),
              ),
        ],
      );
      if (action == null || !mounted || !context.mounted) return;
      // 菜单打开后设备可能断线、被删除或停止 AirPlay，禁止继续使用旧快照。
      final currentList = mergeAirPlayDevicesIntoList(
        ref.read(deviceRegistryProvider),
        ref.read(airplaySessionProvider),
      );
      final current = currentList.devices
          .where((item) => item.id == device.id)
          .firstOrNull;
      final currentSession = currentList.sessionByDeviceId[device.id];
      if (current == null ||
          !action.isEnabledFor(
            current,
            hasAirPlaySession: currentSession != null,
          )) {
        return;
      }
      _setDeviceQuickActionRunning(true);
      await _runDeviceContextAction(context, action, current, currentSession);
    } catch (error) {
      if (mounted && context.mounted) {
        _showSnack(
          context,
          '${context.l10n.t('error')}: $error',
          isError: true,
        );
      }
    } finally {
      _deviceContextMenuOpen = false;
      if (mounted) _setDeviceQuickActionRunning(false);
    }
  }

  IconData _deviceContextActionIcon(DeviceContextAction action) =>
      switch (action) {
        DeviceContextAction.screenshot => CupertinoIcons.camera,
        DeviceContextAction.mirror => CupertinoIcons.tv,
        DeviceContextAction.overview => CupertinoIcons.info,
        DeviceContextAction.apps => AppNavigationIcons.apps,
        DeviceContextAction.files => AppNavigationIcons.files,
        DeviceContextAction.terminal => AppNavigationIcons.terminal,
        DeviceContextAction.edit => CupertinoIcons.pencil,
      };
}
