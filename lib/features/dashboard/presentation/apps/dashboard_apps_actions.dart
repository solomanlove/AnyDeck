part of '../dashboard_screen.dart';

class _PackageActions extends ConsumerWidget {
  const _PackageActions({required this.deviceId, required this.package});

  final String deviceId;
  final AdbPackage package;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(appManagementServiceProvider);
    final packageName = package.name;

    return IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(36),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: context.l10n.t('appDetails'),
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              _showAppDetailsDialog(context, ref, deviceId, package);
            },
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('permissions'),
            icon: const Icon(Icons.security),
            onPressed: () {
              _showAppPermissionsDialog(context, ref, deviceId, package);
            },
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('revokeAllPermissions'),
            icon: const Icon(Icons.lock_open),
            onPressed: () async {
              final confirmed = await _confirm(
                context,
                context.l10n
                    .t('revokeAllPermissionsConfirm')
                    .replaceAll('{package}', packageName),
              );
              if (!confirmed || !context.mounted) return;

              final permissionService = ref.read(appPermissionServiceProvider);
              _showSnack(context, context.l10n.t('revokingAll'));

              final count =
                  await permissionService.revokeAllRuntimePermissions(
                    deviceId,
                    packageName,
                  );

              if (!context.mounted) return;

              if (count > 0) {
                _showSnack(
                  context,
                  context.l10n
                      .t('revokeAllPermissionsSuccess')
                      .replaceAll('{count}', count.toString()),
                );
              } else {
                _showSnack(
                  context,
                  context.l10n.t('revokeAllPermissionsNone'),
                  isError: true,
                );
              }
            },
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('openSystemAppInfo'),
            icon: const Icon(Icons.app_settings_alt_outlined),
            onPressed: () => _runAdbAction(
              context,
              ref,
              service.openAppInfo(deviceId, packageName),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('launch'),
            icon: const Icon(Icons.play_arrow),
            onPressed: () => _runAdbAction(
              context,
              ref,
              service.launch(deviceId, packageName),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('forceStop'),
            icon: const Icon(Icons.stop),
            onPressed: () => _runAdbAction(
              context,
              ref,
              service.forceStop(deviceId, packageName),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('packagePath'),
            icon: const Icon(Icons.route),
            onPressed: () => _showAdbResult(
              context,
              ref,
              service.packagePath(deviceId, packageName),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('clearData'),
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: () async {
              final confirmed = await _confirm(
                context,
                context.l10n
                    .t('clearDataFor')
                    .replaceAll('{package}', packageName),
              );
              if (confirmed && context.mounted) {
                await _runAdbAction(
                  context,
                  ref,
                  service.clearData(deviceId, packageName),
                );
              }
            },
          ),
          const SizedBox(width: 2),
          // 冻结/解冻按钮：根据应用当前启用状态显示对应操作
          IconButton(
            tooltip: package.enabled
                ? context.l10n.t('freezeApp')
                : context.l10n.t('unfreezeApp'),
            icon: Icon(
              package.enabled ? Icons.ac_unit : Icons.local_fire_department,
            ),
            onPressed: () async {
              final confirmMsg = package.enabled
                  ? context.l10n
                        .t('freezeAppConfirm')
                        .replaceAll('{package}', packageName)
                  : context.l10n
                        .t('unfreezeAppConfirm')
                        .replaceAll('{package}', packageName);
              final confirmed = await _confirm(context, confirmMsg);
              if (confirmed && context.mounted) {
                final result = package.enabled
                    ? await service.freezeApp(deviceId, packageName)
                    : await service.unfreezeApp(deviceId, packageName);
                if (context.mounted) {
                  final successMsg = package.enabled
                      ? context.l10n
                            .t('freezeSuccess')
                            .replaceAll('{package}', packageName)
                      : context.l10n
                            .t('unfreezeSuccess')
                            .replaceAll('{package}', packageName);
                  _showSnack(
                    context,
                    result.isSuccess ? successMsg : result.message,
                    isError: !result.isSuccess,
                  );
                }
                if (result.isSuccess) {
                  await service.refreshPackages(deviceId);
                  ref.invalidate(packagesProvider(deviceId));
                }
              }
            },
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('uninstall'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final confirmed = await _confirm(
                context,
                context.l10n
                    .t('uninstallPackage')
                    .replaceAll('{package}', packageName),
              );
              if (confirmed && context.mounted) {
                final result = await service.uninstall(deviceId, packageName);
                if (context.mounted) {
                  _showSnack(
                    context,
                    result.message,
                    isError: !result.isSuccess,
                  );
                }
                if (result.isSuccess) {
                  await service.refreshPackages(deviceId);
                  ref.invalidate(packagesProvider(deviceId));
                }
              }
            },
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('exportApk'),
            icon: const Icon(Icons.download),
            onPressed: () async {
              final directory = await getDirectoryPath();
              if (directory == null || !context.mounted) {
                return;
              }
              final safeLabel = package.displayName.replaceAll(
                RegExp(r'[\\/:*?"<>|]'),
                '_',
              );
              final versionStr = package.versionName != null
                  ? '_v${package.versionName}'
                  : '';
              final fileName = '$safeLabel$versionStr.apk';
              final localSavePath = '$directory/$fileName';

              _showSnack(context, context.l10n.t('exporting'));

              final result = await service.exportApk(
                deviceId,
                packageName,
                localSavePath,
                apkPath: package.apkPath,
              );

              if (context.mounted) {
                final successMsg = context.l10n
                    .t('exportSuccess')
                    .replaceAll('{path}', localSavePath);
                final failMsg = context.l10n
                    .t('exportFailed')
                    .replaceAll('{error}', result.message);
                _showSnack(
                  context,
                  result.isSuccess ? successMsg : failMsg,
                  isError: !result.isSuccess,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

/// `/` 及其子目录的远程文件浏览器。
