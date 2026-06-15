part of '../dashboard_screen.dart';

class _PackageActions extends ConsumerWidget {
  const _PackageActions({required this.deviceId, required this.package});

  final String deviceId;
  final AdbPackage package;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(appManagementServiceProvider);
    final packageName = package.name;
    final isOnline = ref.watch(deviceOnlineProvider(deviceId));

    return AbsorbPointer(
      absorbing: !isOnline,
      child: Opacity(
        opacity: isOnline ? 1.0 : 0.5,
        child: IconButtonTheme(
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
            icon: const Icon(CupertinoIcons.info),
            onPressed: () {
              _showAppDetailsDialog(context, ref, deviceId, package);
            },
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('permissions'),
            icon: const Icon(CupertinoIcons.shield),
            onPressed: () {
              _showAppPermissionsDialog(context, ref, deviceId, package);
            },
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('revokeAllPermissions'),
            icon: const Icon(CupertinoIcons.lock_open),
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

              final count = await permissionService.revokeAllRuntimePermissions(
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
            icon: const Icon(CupertinoIcons.settings),
            onPressed: () => _runAdbAction(
              context,
              ref,
              service.openAppInfo(deviceId, packageName),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('launch'),
            icon: const Icon(CupertinoIcons.play),
            onPressed: () => _runAdbAction(
              context,
              ref,
              service.launch(deviceId, packageName),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('appMirroring'),
            icon: const Icon(Icons.cast),
            onPressed: () async {
              final windowTitle = context.l10n
                  .t('screenMirrorTitle')
                  .replaceAll('{name}', package.displayName);
              // 1. 如果内嵌投屏处于活跃状态，先停止内嵌投屏
              final textureId = ref.read(activeEmbeddedMirrorProvider(deviceId));
              if (textureId != null) {
                await ref
                    .read(activeEmbeddedMirrorProvider(deviceId).notifier)
                    .forceStop();
              }

              // 2. 打开独立的内嵌投屏窗口并传入包名和副屏参数
              try {
                final overviewAsync = ref.read(deviceOverviewProvider(deviceId));
                final resolution = overviewAsync.maybeWhen(
                  data: (overview) => overview.physicalResolution,
                  orElse: () => null,
                );
                
                // 默认使用 1080x1920 竖屏作为虚拟副屏的初始分辨率，
                // 如果能获取到设备的物理分辨率，则保持相同的宽度，并根据比例自适应或者直接使用竖屏比例
                String vdResolution = '1080x1920';
                if (resolution != null && resolution.contains('x')) {
                  final parts = resolution.split('x');
                  if (parts.length == 2) {
                    final w = int.tryParse(parts[0].trim());
                    final h = int.tryParse(parts[1].trim());
                    if (w != null && h != null) {
                      // 确保是竖屏比例，即较小的数在前，较大的数在后
                      final minSide = w < h ? w : h;
                      final maxSide = w > h ? w : h;
                      // 限制最大边在合适范围内，比如 1920
                      double scale = 1.0;
                      if (maxSide > 1920) {
                        scale = 1920 / maxSide;
                      }
                      final targetW = ((minSide * scale).toInt() ~/ 2) * 2; // 确保偶数
                      final targetH = ((maxSide * scale).toInt() ~/ 2) * 2;
                      vdResolution = '${targetW}x$targetH';
                    }
                  }
                }

                final initialSize = _resolveMirrorInitialWindowSize(resolution);

                await createAdbManageWindow(
                  arguments: {
                    'type': 'mirror',
                    'deviceId': deviceId,
                    'deviceName': package.displayName, // 窗口标题显示应用名
                    'newDisplay': vdResolution,
                    'startApp': packageName,
                  },
                  frame: Offset.zero & initialSize,
                  title: windowTitle,
                );
              } catch (e) {
                if (context.mounted) {
                  _showSnack(
                    context,
                    context.l10n
                        .t('appMirroringFailed')
                        .replaceAll('{error}', e.toString()),
                    isError: true,
                  );
                }
              }
            },
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('forceStop'),
            icon: const Icon(CupertinoIcons.stop),
            onPressed: () => _runAdbAction(
              context,
              ref,
              service.forceStop(deviceId, packageName),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('packagePath'),
            icon: const Icon(CupertinoIcons.arrow_merge),
            onPressed: () => _showAdbResult(
              context,
              ref,
              service.packagePath(deviceId, packageName),
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('clearData'),
            icon: const Icon(CupertinoIcons.clear),
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
          IconButton(
            tooltip: context.l10n.t('backupAppData'),
            icon: const Icon(CupertinoIcons.archivebox),
            onPressed: () => _backupAppData(context, ref, deviceId, package),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('restoreAppData'),
            icon: const Icon(Icons.restore),
            onPressed: () => _restoreAppData(context, ref, deviceId, package),
          ),
          const SizedBox(width: 2),
          // 冻结/解冻按钮：根据应用当前启用状态显示对应操作
          IconButton(
            tooltip: package.enabled
                ? context.l10n.t('freezeApp')
                : context.l10n.t('unfreezeApp'),
            icon: Icon(
              package.enabled ? CupertinoIcons.snow : CupertinoIcons.flame,
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
                  await service.clearPackageCache(deviceId);
                  ref.invalidate(packagesProvider(deviceId));
                }
              }
            },
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('uninstall'),
            icon: const Icon(CupertinoIcons.trash),
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
                  await service.clearPackageCache(deviceId);
                  ref.invalidate(packagesProvider(deviceId));
                }
              }
            },
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('exportApk'),
            icon: const Icon(CupertinoIcons.cloud_download),
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
          const SizedBox(width: 2),
          IconButton(
            tooltip: context.l10n.t('refreshSingleApp'),
            icon: const Icon(CupertinoIcons.arrow_2_circlepath),
            onPressed: () async {
              _showSnack(
                context,
                context.l10n
                    .t('refreshingApp')
                    .replaceAll('{package}', package.displayName),
              );
              try {
                await ref
                    .read(packagesProvider(deviceId).notifier)
                    .refreshSinglePackage(packageName);
                if (context.mounted) {
                  _showSnack(
                    context,
                    context.l10n
                        .t('refreshSingleAppSuccess')
                        .replaceAll('{package}', package.displayName),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  _showSnack(
                    context,
                    context.l10n
                        .t('refreshSingleAppFailed')
                        .replaceAll('{package}', package.displayName)
                        .replaceAll('{error}', e.toString()),
                    isError: true,
                  );
                }
              }
            },
          ),
        ],
      ),
    ),
      ),
    );
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
