part of '../dashboard_screen.dart';

/// Android 单应用菜单定义，文案和图标与原快捷操作保持一致。
enum _AndroidAppAction {
  details(CupertinoIcons.info, 'appDetails'),
  permissions(CupertinoIcons.shield, 'permissions'),
  revokePermissions(CupertinoIcons.lock_open, 'revokeAllPermissions'),
  systemInfo(CupertinoIcons.settings, 'openSystemAppInfo'),
  launch(CupertinoIcons.play, 'launch'),
  mirror(Icons.cast, 'primaryAppTooltip'),
  forceStop(CupertinoIcons.stop, 'forceStop'),
  packagePath(CupertinoIcons.arrow_merge, 'packagePath'),
  clearData(CupertinoIcons.clear, 'clearData'),
  backup(CupertinoIcons.archivebox, 'backupAppData'),
  restore(Icons.restore, 'restoreAppData'),
  freeze(CupertinoIcons.snow, 'freezeApp'),
  refresh(CupertinoIcons.arrow_2_circlepath, 'refreshSingleApp');

  const _AndroidAppAction(this.icon, this.labelKey);

  final IconData icon;
  final String labelKey;
}

/// 列表与网格共用右键入口；仅选中目标项，不触发详情读取或批量勾选。
extension _AppsContextMenu on _AppsTabState {
  bool _canRunAppAction(String deviceId) =>
      mounted &&
      widget.device.id == deviceId &&
      ref.read(deviceOnlineProvider(deviceId));

  Future<void> _showAppContextMenu(AdbPackage package, Offset position) async {
    if (!mounted || _appContextMenuOpen || _runningAppAction) return;
    final deviceId = widget.device.id;
    _updateAppView(() => _selectedPackage = package.name);
    _appContextMenuOpen = true;
    try {
      if (widget.device.isHarmony) {
        await _showHarmonyAppContextMenu(package, position);
        return;
      }

      final overlay =
          Navigator.of(
                context,
                rootNavigator: true,
              ).overlay?.context.findRenderObject()
              as RenderBox?;
      if (overlay == null) return;
      final localPosition = overlay.globalToLocal(position);
      final fusionMode = ref
          .read(deviceFusionModeProvider(deviceId))
          .asData
          ?.value;
      final isOnline = ref.read(deviceOnlineProvider(deviceId));
      final theme = Theme.of(context);
      final action = await showMenu<_AndroidAppAction>(
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
          for (final action in _AndroidAppAction.values)
            PopupMenuItem<_AndroidAppAction>(
              value: action,
              enabled: isOnline,
              height: 36,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    action == _AndroidAppAction.freeze && !package.enabled
                        ? CupertinoIcons.flame
                        : action.icon,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      context.l10n.t(switch (action) {
                        _AndroidAppAction.freeze when !package.enabled =>
                          'unfreezeApp',
                        _AndroidAppAction.mirror
                            when fusionMode?.state == FusionModeState.enabled =>
                          'fusionAppTooltip',
                        _ => action.labelKey,
                      }),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
      // 菜单打开期间可能切换设备或断线，执行前再次校验操作对象。
      if (action == null || !_canRunAppAction(deviceId)) return;
      _runningAppAction = true;
      await _runAndroidAppAction(action, deviceId, package);
    } catch (error) {
      if (mounted) _showSnack(context, error.toString(), isError: true);
    } finally {
      _runningAppAction = false;
      _appContextMenuOpen = false;
    }
  }
}
