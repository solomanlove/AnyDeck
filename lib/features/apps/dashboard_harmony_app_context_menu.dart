part of '../dashboard_screen.dart';

enum _HarmonyAppAction {
  details,
  launch,
  forceStop,
  clearCache,
  clearData,
  uninstall,
  refresh,
}

/// 鸿蒙应用右键菜单：仅展示当前 HDC 实现支持的单应用操作。
extension _HarmonyAppContextMenu on _AppsTabState {
  Future<void> _showHarmonyAppContextMenu(
    AdbPackage package,
    Offset position,
  ) async {
    if (!mounted || !widget.device.isHarmony) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final action = await showMenu<_HarmonyAppAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      items: [
        _harmonyMenuItem(
          _HarmonyAppAction.details,
          CupertinoIcons.info,
          'appDetails',
        ),
        _harmonyMenuItem(
          _HarmonyAppAction.launch,
          CupertinoIcons.play,
          'launch',
        ),
        _harmonyMenuItem(
          _HarmonyAppAction.forceStop,
          CupertinoIcons.stop,
          'forceStop',
        ),
        _harmonyMenuItem(
          _HarmonyAppAction.clearCache,
          CupertinoIcons.clear_circled,
          'clearAppCache',
        ),
        _harmonyMenuItem(
          _HarmonyAppAction.clearData,
          CupertinoIcons.clear,
          'clearData',
        ),
        _harmonyMenuItem(
          _HarmonyAppAction.uninstall,
          CupertinoIcons.trash,
          'uninstall',
        ),
        _harmonyMenuItem(
          _HarmonyAppAction.refresh,
          CupertinoIcons.refresh,
          'refreshSingleApp',
        ),
      ],
    );
    if (action == null || !mounted) return;
    final deviceId = widget.device.id;
    final packageName = package.name;
    final service = ref.read(appManagementServiceProvider);
    switch (action) {
      case _HarmonyAppAction.details:
        await _openPackage(packageName);
      case _HarmonyAppAction.launch:
        await _showHarmonyResult(
          service.launch(deviceId, packageName, isHarmony: true),
        );
      case _HarmonyAppAction.forceStop:
        await _showHarmonyResult(
          service.forceStop(deviceId, packageName, isHarmony: true),
        );
      case _HarmonyAppAction.clearCache:
        if (await _confirm(
              context,
              context.l10n
                  .t('clearAppCacheFor')
                  .replaceAll('{package}', packageName),
            ) &&
            mounted &&
            _clearingHarmonyCache.add(packageName)) {
          try {
            await _showHarmonyResult(
              service.clearHarmonyCache(deviceId, packageName),
            );
          } catch (error) {
            if (mounted) {
              _showSnack(
                context,
                context.l10n
                    .t('clearAppCacheFailed')
                    .replaceAll('{error}', '$error'),
                isError: true,
              );
            }
          } finally {
            _clearingHarmonyCache.remove(packageName);
          }
        }
      case _HarmonyAppAction.clearData:
        if (await _confirm(
              context,
              context.l10n
                  .t('clearDataFor')
                  .replaceAll('{package}', packageName),
            ) &&
            mounted) {
          await _showHarmonyResult(
            service.clearData(deviceId, packageName, isHarmony: true),
          );
        }
      case _HarmonyAppAction.uninstall:
        if (await _confirm(
              context,
              context.l10n
                  .t('uninstallPackage')
                  .replaceAll('{package}', packageName),
            ) &&
            mounted) {
          final result = await service.uninstall(
            deviceId,
            packageName,
            isHarmony: true,
          );
          if (result.isSuccess) {
            await ref.read(packagesProvider(deviceId).notifier).removePackages({
              packageName,
            });
          }
          if (mounted)
            _showSnack(context, result.message, isError: !result.isSuccess);
        }
      case _HarmonyAppAction.refresh:
        await ref
            .read(packagesProvider(deviceId).notifier)
            .refreshSinglePackage(packageName);
    }
  }

  /// 将 HDC 命令结果反馈在当前页面，避免右键操作静默失败。
  Future<void> _showHarmonyResult(Future<AdbResult> task) async {
    final result = await task;
    if (mounted)
      _showSnack(context, result.message, isError: !result.isSuccess);
  }

  PopupMenuItem<_HarmonyAppAction> _harmonyMenuItem(
    _HarmonyAppAction action,
    IconData icon,
    String labelKey,
  ) => PopupMenuItem<_HarmonyAppAction>(
    value: action,
    height: 38,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 8),
        Text(context.l10n.t(labelKey)),
      ],
    ),
  );
}
