part of '../dashboard_screen.dart';

/// 单应用菜单动作编排，复用既有服务、确认弹窗与结果反馈。
extension _AndroidAppActions on _AppsTabState {
  Future<void> _runAndroidAppAction(
    _AndroidAppAction action,
    String deviceId,
    AdbPackage package,
  ) async {
    final service = ref.read(appManagementServiceProvider);
    final packageName = package.name;
    switch (action) {
      case _AndroidAppAction.details:
        await _openPackage(packageName);
      case _AndroidAppAction.permissions:
        _showAppPermissionsDialog(context, ref, deviceId, package);
      case _AndroidAppAction.revokePermissions:
        await _revokePackagePermissions(deviceId, packageName);
      case _AndroidAppAction.systemInfo:
        await _runAdbAction(
          context,
          ref,
          service.openAppInfo(deviceId, packageName),
        );
      case _AndroidAppAction.launch:
        await _runAdbAction(
          context,
          ref,
          service.launch(deviceId, packageName),
        );
      case _AndroidAppAction.mirror:
        await _mirrorPackage(deviceId, package);
      case _AndroidAppAction.forceStop:
        await _runAdbAction(
          context,
          ref,
          service.forceStop(deviceId, packageName),
        );
      case _AndroidAppAction.packagePath:
        await _showAdbResult(
          context,
          ref,
          service.packagePath(deviceId, packageName),
        );
      case _AndroidAppAction.clearData:
        final confirmed = await _confirm(
          context,
          context.l10n.t('clearDataFor').replaceAll('{package}', packageName),
        );
        if (confirmed && mounted && _canRunAppAction(deviceId)) {
          await _runAdbAction(
            context,
            ref,
            service.clearData(deviceId, packageName),
          );
        }
      case _AndroidAppAction.backup:
        await _backupAppData(context, ref, deviceId, package);
      case _AndroidAppAction.restore:
        await _restoreAppData(context, ref, deviceId, package);
      case _AndroidAppAction.freeze:
        await _togglePackageEnabled(deviceId, package);
      case _AndroidAppAction.refresh:
        await _refreshPackageDetails(deviceId, package);
    }
  }

  /// 撤销全部动态权限前保留原有确认与处理结果提示。
  Future<void> _revokePackagePermissions(
    String deviceId,
    String packageName,
  ) async {
    final confirmed = await _confirm(
      context,
      context.l10n
          .t('revokeAllPermissionsConfirm')
          .replaceAll('{package}', packageName),
    );
    if (!confirmed || !mounted || !_canRunAppAction(deviceId)) return;

    final service = ref.read(appPermissionServiceProvider);
    _showSnack(context, context.l10n.t('revokingAll'));
    final count = await service.revokeAllRuntimePermissions(
      deviceId,
      packageName,
    );
    if (!mounted) return;
    _showSnack(
      context,
      count > 0
          ? context.l10n
                .t('revokeAllPermissionsSuccess')
                .replaceAll('{count}', count.toString())
          : context.l10n.t('revokeAllPermissionsNone'),
      isError: count == 0,
    );
  }

  /// 投屏继续由协调器选择融合副屏或普通主屏，并复用已有窗口。
  Future<void> _mirrorPackage(String deviceId, AdbPackage package) async {
    try {
      final overviewAsync = ref.read(deviceOverviewProvider(deviceId));
      final resolution = overviewAsync.maybeWhen(
        data: (overview) => overview.physicalResolution,
        orElse: () => null,
      );
      final videoSize = ref
          .read(embeddedScrcpyServiceProvider)
          .getVideoSize(deviceId);
      final matchingDev = ref
          .read(deviceRegistryProvider)
          .firstWhere(
            (device) => device.id == deviceId,
            orElse: () => RegisteredDevice(
              id: deviceId,
              status: 'unknown',
              isOnline: false,
            ),
          );
      final result = await ref
          .read(appMirrorLaunchCoordinatorProvider)
          .open(
            AppMirrorLaunchRequest(
              deviceId: deviceId,
              packageName: package.name,
              appName: package.displayName,
              mirrorTitleTemplate: context.l10n.t('screenMirrorTitle'),
              alwaysOnTop: ref.read(appSettingsProvider).scrcpyAlwaysOnTop,
              device: matchingDev,
              physicalResolution: resolution,
              videoWidth: videoSize?['width'],
              videoHeight: videoSize?['height'],
            ),
          );
      if (mounted && result.kind == AppMirrorLaunchKind.existingFusion) {
        _showSnack(context, context.l10n.t('fusionExistingWindow'));
      }
      if (mounted && result.kind == AppMirrorLaunchKind.primaryUnknown) {
        _showSnack(context, context.l10n.t('fusionDetectionFallback'));
      }
    } catch (error) {
      if (mounted) {
        _showSnack(
          context,
          context.l10n
              .t('appMirroringFailed')
              .replaceAll('{error}', error.toString()),
          isError: true,
        );
      }
    }
  }

  /// 冻结/解冻依当前应用状态执行，成功后回读更新列表状态。
  Future<void> _togglePackageEnabled(
    String deviceId,
    AdbPackage package,
  ) async {
    final confirmed = await _confirm(
      context,
      context.l10n
          .t(package.enabled ? 'freezeAppConfirm' : 'unfreezeAppConfirm')
          .replaceAll('{package}', package.name),
    );
    if (!confirmed || !_canRunAppAction(deviceId)) return;
    final service = ref.read(appManagementServiceProvider);
    final result = package.enabled
        ? await service.freezeApp(deviceId, package.name)
        : await service.unfreezeApp(deviceId, package.name);
    if (!mounted) return;
    final successMessage = context.l10n
        .t(package.enabled ? 'freezeSuccess' : 'unfreezeSuccess')
        .replaceAll('{package}', package.name);
    _showSnack(
      context,
      result.isSuccess ? successMessage : result.message,
      isError: !result.isSuccess,
    );
    if (result.isSuccess) {
      await ref
          .read(packagesProvider(deviceId).notifier)
          .refreshSinglePackage(package.name);
    }
  }

  /// 右键刷新只更新目标应用，沿用原有进度与成功/失败文案。
  Future<void> _refreshPackageDetails(
    String deviceId,
    AdbPackage package,
  ) async {
    _showSnack(
      context,
      context.l10n
          .t('refreshingApp')
          .replaceAll('{package}', package.displayName),
    );
    try {
      await ref
          .read(packagesProvider(deviceId).notifier)
          .refreshSinglePackage(package.name);
      if (mounted) {
        _showSnack(
          context,
          context.l10n
              .t('refreshSingleAppSuccess')
              .replaceAll('{package}', package.displayName),
        );
      }
    } catch (error) {
      if (mounted) {
        _showSnack(
          context,
          context.l10n
              .t('refreshSingleAppFailed')
              .replaceAll('{package}', package.displayName)
              .replaceAll('{error}', error.toString()),
          isError: true,
        );
      }
    }
  }
}

Future<void> _backupAppData(
  BuildContext context,
  WidgetRef ref,
  String deviceId,
  AdbPackage package,
) async {
  final directory = await getDirectoryPath();
  if (directory == null || !context.mounted) {
    return;
  }

  _showSnack(context, context.l10n.t('backupAppDataRunning'));
  final service = ref.read(appDataBackupServiceProvider);
  final result = await service.backupData(
    deviceId,
    package.name,
    directory,
    displayName: package.displayName,
    versionName: package.versionName,
  );

  if (!context.mounted) {
    return;
  }
  final message = result.isSuccess
      ? context.l10n
            .t('backupAppDataSuccess')
            .replaceAll('{path}', result.stdout)
      : context.l10n
            .t('backupAppDataFailed')
            .replaceAll('{error}', result.message);
  _showSnack(context, message, isError: !result.isSuccess);
}

Future<void> _restoreAppData(
  BuildContext context,
  WidgetRef ref,
  String deviceId,
  AdbPackage package,
) async {
  final confirmed = await _confirm(
    context,
    context.l10n
        .t('restoreAppDataConfirm')
        .replaceAll('{package}', package.name),
  );
  if (!confirmed || !context.mounted) {
    return;
  }

  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'App data backup', extensions: ['ab', 'tar']),
    ],
  );
  if (file == null || !context.mounted) {
    return;
  }

  _showSnack(context, context.l10n.t('restoreAppDataRunning'));
  final service = ref.read(appDataBackupServiceProvider);
  final result = await service.restoreData(deviceId, package.name, file.path);

  if (!context.mounted) {
    return;
  }
  final message = result.isSuccess
      ? context.l10n.t('restoreAppDataSuccess')
      : context.l10n
            .t('restoreAppDataFailed')
            .replaceAll('{error}', result.message);
  _showSnack(context, message, isError: !result.isSuccess);
}

/// `/` 及其子目录的远程文件浏览器。
