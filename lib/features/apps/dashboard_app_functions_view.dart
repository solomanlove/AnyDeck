part of '../dashboard_screen.dart';

class _AppFunctionsView extends ConsumerStatefulWidget {
  const _AppFunctionsView({
    required this.deviceId,
    required this.package,
    required this.onBack,
  });

  final String deviceId;
  final AdbPackage package;
  final VoidCallback onBack;

  @override
  ConsumerState<_AppFunctionsView> createState() => _AppFunctionsViewState();
}

class _AppFunctionsViewState extends ConsumerState<_AppFunctionsView> {
  late Future<AdbPackageDetail> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = ref
        .read(appManagementServiceProvider)
        .getPackageDetailedInfo(widget.deviceId, widget.package.name);
  }

  @override
  Widget build(BuildContext context) {
    final deviceId = widget.deviceId;
    final package = widget.package;
    final onBack = widget.onBack;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isOnline = ref.watch(deviceOnlineProvider(deviceId));
    final service = ref.read(appManagementServiceProvider);
    final packageName = package.name;
    final isHarmony = ref.read(deviceRegistryProvider).any(
      (d) => d.id == deviceId && d.isHarmony,
    );

    final Color cardBg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.white.withValues(alpha: 0.5);

    final titleColor = isDark
        ? const Color(0xffeceff1)
        : const Color(0xff202124);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Navigation Header
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.03),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(CupertinoIcons.arrow_left),
                tooltip: context.l10n.t('back'),
                onPressed: onBack,
              ),
              const SizedBox(width: 12),
              Text(
                "应用管理",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: titleColor.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "/",
                style: TextStyle(
                  color: titleColor.withValues(alpha: 0.3),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  package.displayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.arrow_2_circlepath),
                tooltip: context.l10n.t('refreshSingleApp'),
                onPressed: isOnline
                    ? () async {
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
                          if (mounted) {
                            setState(() {
                              _detailsFuture = ref
                                  .read(appManagementServiceProvider)
                                  .getPackageDetailedInfo(
                                    deviceId,
                                    packageName,
                                  );
                            });
                          }
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
                      }
                    : null,
              ),
            ],
          ),
        ),

        // Content Area
        Expanded(
          child: FutureBuilder<AdbPackageDetail>(
            future: _detailsFuture,
            builder: (context, snapshot) {
              final detail = snapshot.data;
              final isLoading =
                  snapshot.connectionState == ConnectionState.waiting;
              final error = snapshot.error;

              return DefaultTabController(
                length: 10,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final useHorizontalLayout = constraints.maxWidth >= 720;

                    final summaryCard = SizedBox(
                      width: useHorizontalLayout ? 300 : double.infinity,
                      child: _AppDetailSummaryCard(
                        deviceId: deviceId,
                        package: package,
                        cardBg: cardBg,
                        isDark: isDark,
                        useHorizontalLayout: useHorizontalLayout,
                        detail: detail,
                      ),
                    );

                    final tabbedContent = Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            tabs: [
                              const Tab(text: '功能操作'),
                              Tab(
                                text:
                                    '原生库${detail != null ? ' (${detail.libs.length})' : ''}',
                              ),
                              Tab(
                                text:
                                    '服务${detail != null ? ' (${detail.services.length})' : ''}',
                              ),
                              Tab(
                                text:
                                    '活动${detail != null ? ' (${detail.activities.length})' : ''}',
                              ),
                              Tab(
                                text:
                                    '广播接收器${detail != null ? ' (${detail.receivers.length})' : ''}',
                              ),
                              Tab(
                                text:
                                    '内容提供者${detail != null ? ' (${detail.providers.length})' : ''}',
                              ),
                              Tab(
                                text:
                                    '权限${detail != null ? ' (${detail.permissions.length})' : ''}',
                              ),
                              Tab(
                                text:
                                    '元数据${detail != null ? ' (${detail.metadata.length})' : ''}',
                              ),
                              Tab(
                                text:
                                    'DEX${detail != null ? ' (${detail.dexFiles.length})' : ''}',
                              ),
                              Tab(text: context.l10n.t('appSignature')),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                if (isLoading) {
                                  return const Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        CircularProgressIndicator(),
                                        SizedBox(height: 12),
                                        Text('正在深入分析应用细节，请稍候...'),
                                      ],
                                    ),
                                  );
                                }

                                if (error != null || detail == null) {
                                  return Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          CupertinoIcons
                                              .exclamationmark_triangle,
                                          color: Colors.orange,
                                          size: 40,
                                        ),
                                        const SizedBox(height: 12),
                                        Text('分析失败: ${error ?? '无数据'}'),
                                        const SizedBox(height: 12),
                                        ElevatedButton(
                                          onPressed: () {
                                            setState(() {
                                              _detailsFuture = ref
                                                  .read(
                                                    appManagementServiceProvider,
                                                  )
                                                  .getPackageDetailedInfo(
                                                    widget.deviceId,
                                                    widget.package.name,
                                                  );
                                            });
                                          },
                                          child: const Text('重试'),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                return TabBarView(
                                  children: [
                                    // Tab 1: 功能操作
                                    SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            "功能操作",
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: titleColor,
                                                ),
                                          ),
                                          const SizedBox(height: 16),
                                          GridView.extent(
                                            maxCrossAxisExtent: 320,
                                            mainAxisSpacing: 12,
                                            crossAxisSpacing: 12,
                                            childAspectRatio: 2.8,
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            children: [
                                              _AppActionButtonCard(
                                                icon: CupertinoIcons.play,
                                                title: "启动应用",
                                                description: "运行并启动此应用的主界面",
                                                iconColor: const Color(
                                                  0xFF2EC46B,
                                                ),
                                                onPressed: isOnline
                                                    ? () => _runAdbAction(
                                                        context,
                                                        ref,
                                                        service.launch(
                                                          deviceId,
                                                          packageName,
                                                          isHarmony: isHarmony,
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                              _AppActionButtonCard(
                                                icon: CupertinoIcons.stop,
                                                title: "强行停止",
                                                description: "强行关闭此应用的所有后台进程",
                                                iconColor: const Color(
                                                  0xFFE53935,
                                                ),
                                                onPressed: isOnline
                                                    ? () => _runAdbAction(
                                                        context,
                                                        ref,
                                                        service.forceStop(
                                                          deviceId,
                                                          packageName,
                                                          isHarmony: isHarmony,
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                              _AppActionButtonCard(
                                                icon: CupertinoIcons.clear,
                                                title: "清除数据",
                                                description: "清除所有应用数据及缓存",
                                                iconColor: const Color(
                                                  0xFFFB8C00,
                                                ),
                                                onPressed: isOnline
                                                    ? () async {
                                                        final confirmed =
                                                            await _confirm(
                                                              context,
                                                              context.l10n
                                                                  .t(
                                                                    'clearDataFor',
                                                                  )
                                                                  .replaceAll(
                                                                    '{package}',
                                                                    packageName,
                                                                  ),
                                                            );
                                                        if (confirmed &&
                                                            context.mounted) {
                                                          await _runAdbAction(
                                                            context,
                                                            ref,
                                                            service.clearData(
                                                              deviceId,
                                                              packageName,
                                                              isHarmony: isHarmony,
                                                            ),
                                                          );
                                                        }
                                                      }
                                                    : null,
                                              ),
                                              _AppActionButtonCard(
                                                icon: package.enabled
                                                    ? CupertinoIcons.snow
                                                    : CupertinoIcons.flame,
                                                title: package.enabled
                                                    ? "冻结应用"
                                                    : "解冻应用",
                                                description: package.enabled
                                                    ? "禁用并隐藏此应用"
                                                    : "恢复并启用此应用",
                                                iconColor: const Color(
                                                  0xFF0288D1,
                                                ),
                                                onPressed: isOnline
                                                    ? () async {
                                                        final confirmMsg =
                                                            package.enabled
                                                            ? context.l10n
                                                                  .t(
                                                                    'freezeAppConfirm',
                                                                  )
                                                                  .replaceAll(
                                                                    '{package}',
                                                                    packageName,
                                                                  )
                                                            : context.l10n
                                                                  .t(
                                                                    'unfreezeAppConfirm',
                                                                  )
                                                                  .replaceAll(
                                                                    '{package}',
                                                                    packageName,
                                                                  );
                                                        final confirmed =
                                                            await _confirm(
                                                              context,
                                                              confirmMsg,
                                                            );
                                                        if (confirmed &&
                                                            context.mounted) {
                                                          final result =
                                                              package.enabled
                                                              ? await service
                                                                    .freezeApp(
                                                                      deviceId,
                                                                      packageName,
                                                                      isHarmony: isHarmony,
                                                                    )
                                                              : await service
                                                                    .unfreezeApp(
                                                                      deviceId,
                                                                      packageName,
                                                                      isHarmony: isHarmony,
                                                                    );
                                                          if (context
                                                              .mounted) {
                                                            final successMsg =
                                                                package
                                                                    .enabled
                                                                ? context.l10n
                                                                      .t(
                                                                        'freezeSuccess',
                                                                      )
                                                                      .replaceAll(
                                                                        '{package}',
                                                                        packageName,
                                                                      )
                                                                : context.l10n
                                                                      .t(
                                                                        'unfreezeSuccess',
                                                                      )
                                                                      .replaceAll(
                                                                        '{package}',
                                                                        packageName,
                                                                      );
                                                            _showSnack(
                                                              context,
                                                              result.isSuccess
                                                                  ? successMsg
                                                                  : result
                                                                        .message,
                                                              isError: !result
                                                                  .isSuccess,
                                                            );
                                                          }
                                                          if (result
                                                              .isSuccess) {
                                                            await ref
                                                                .read(
                                                                  packagesProvider(
                                                                    deviceId,
                                                                  ).notifier,
                                                                )
                                                                .refreshSinglePackage(
                                                                  packageName,
                                                                );
                                                          }
                                                        }
                                                      }
                                                    : null,
                                              ),
                                              _AppActionButtonCard(
                                                icon: Icons.cast,
                                                title: "应用投屏",
                                                description: "在虚拟副屏中开启此应用投屏",
                                                iconColor: const Color(
                                                  0xFF8E24AA,
                                                ),
                                                onPressed: isOnline
                                                    ? () async {
                                                        final windowTitle = context
                                                            .l10n
                                                            .t(
                                                              'screenMirrorTitle',
                                                            )
                                                            .replaceAll(
                                                              '{name}',
                                                              package
                                                                  .displayName,
                                                            );
                                                        final textureId = ref
                                                            .read(
                                                              activeEmbeddedMirrorProvider(
                                                                deviceId,
                                                              ),
                                                            );
                                                        if (textureId !=
                                                            null) {
                                                          await ref
                                                              .read(
                                                                activeEmbeddedMirrorProvider(
                                                                  deviceId,
                                                                ).notifier,
                                                              )
                                                              .forceStop();
                                                        }
                                                        try {
                                                          final overviewAsync =
                                                              ref.read(
                                                                deviceOverviewProvider(
                                                                  deviceId,
                                                                ),
                                                              );
                                                          final resolution =
                                                              overviewAsync.maybeWhen(
                                                                data:
                                                                    (
                                                                      overview,
                                                                    ) => overview
                                                                        .physicalResolution,
                                                                orElse: () =>
                                                                    null,
                                                              );
                                                          String
                                                          vdResolution =
                                                              '1080x1920';
                                                          if (resolution !=
                                                                  null &&
                                                              resolution
                                                                  .contains(
                                                                    'x',
                                                                  )) {
                                                            final parts =
                                                                resolution
                                                                    .split(
                                                                      'x',
                                                                    );
                                                            if (parts
                                                                    .length ==
                                                                2) {
                                                              final w =
                                                                  int.tryParse(
                                                                    parts[0]
                                                                        .trim(),
                                                                  );
                                                              final h =
                                                                  int.tryParse(
                                                                    parts[1]
                                                                        .trim(),
                                                                  );
                                                              if (w != null &&
                                                                  h != null) {
                                                                final minSide =
                                                                    w < h
                                                                    ? w
                                                                    : h;
                                                                final maxSide =
                                                                    w > h
                                                                    ? w
                                                                    : h;
                                                                double scale =
                                                                    1.0;
                                                                if (maxSide >
                                                                    1920) {
                                                                  scale =
                                                                      1920 /
                                                                      maxSide;
                                                                }
                                                                final targetW =
                                                                    ((minSide * scale)
                                                                            .toInt() ~/
                                                                        2) *
                                                                    2;
                                                                final targetH =
                                                                    ((maxSide * scale)
                                                                            .toInt() ~/
                                                                        2) *
                                                                    2;
                                                                vdResolution =
                                                                    '${targetW}x$targetH';
                                                              }
                                                            }
                                                          }
                                                          final initialSize =
                                                              _resolveMirrorInitialWindowSize(
                                                                vdResolution,
                                                              );
                                                          final devReg = ref.read(deviceRegistryProvider);
                                                          final matchingDev = devReg.firstWhere(
                                                            (d) => d.id == deviceId,
                                                            orElse: () => RegisteredDevice(id: deviceId, status: 'unknown', isOnline: false),
                                                          );
                                                          await createAdbManageWindow(
                                                            arguments: {
                                                              'type':
                                                                  'mirror',
                                                              'deviceId':
                                                                  deviceId,
                                                              'deviceName':
                                                                  package
                                                                      .displayName,
                                                              'newDisplay':
                                                                  vdResolution,
                                                              'startApp':
                                                                  packageName,
                                                              'alwaysOnTop':
                                                                  ref
                                                                      .read(
                                                                        appSettingsProvider,
                                                                      )
                                                                      .scrcpyAlwaysOnTop,
                                                              'isIos': matchingDev.isIos,
                                                              'isHarmony': matchingDev.isHarmony,
                                                            },
                                                            frame:
                                                                Offset.zero &
                                                                initialSize,
                                                            title:
                                                                windowTitle,
                                                          );
                                                        } catch (e) {
                                                          if (context
                                                              .mounted) {
                                                            _showSnack(
                                                              context,
                                                              context.l10n
                                                                  .t(
                                                                    'appMirroringFailed',
                                                                  )
                                                                  .replaceAll(
                                                                    '{error}',
                                                                    e.toString(),
                                                                  ),
                                                              isError: true,
                                                            );
                                                          }
                                                        }
                                                      }
                                                    : null,
                                              ),
                                              _AppActionButtonCard(
                                                icon: CupertinoIcons.shield,
                                                title: "权限管理",
                                                description: "查看并更改应用被授予的权限",
                                                iconColor: const Color(
                                                  0xFF43A047,
                                                ),
                                                onPressed: isOnline
                                                    ? () {
                                                        DefaultTabController.of(
                                                          context,
                                                        ).animateTo(6);
                                                      }
                                                    : null,
                                              ),
                                              _AppActionButtonCard(
                                                icon:
                                                    CupertinoIcons.lock_open,
                                                title: "重置权限",
                                                description: "撤销当前应用的所有运行时权限",
                                                iconColor: const Color(
                                                  0xFFD81B60,
                                                ),
                                                onPressed: isOnline
                                                    ? () async {
                                                        final confirmed =
                                                            await _confirm(
                                                              context,
                                                              context.l10n
                                                                  .t(
                                                                    'revokeAllPermissionsConfirm',
                                                                  )
                                                                  .replaceAll(
                                                                    '{package}',
                                                                    packageName,
                                                                  ),
                                                            );
                                                        if (!confirmed ||
                                                            !context
                                                                .mounted) {
                                                          return;
                                                        }
                                                        final permissionService =
                                                            ref.read(
                                                              appPermissionServiceProvider,
                                                            );
                                                        _showSnack(
                                                          context,
                                                          context.l10n.t(
                                                            'revokingAll',
                                                          ),
                                                        );
                                                        final count =
                                                            await permissionService
                                                                .revokeAllRuntimePermissions(
                                                                  deviceId,
                                                                  packageName,
                                                                );
                                                        if (!context
                                                            .mounted) {
                                                          return;
                                                        }
                                                        if (count > 0) {
                                                          _showSnack(
                                                            context,
                                                            context.l10n
                                                                .t(
                                                                  'revokeAllPermissionsSuccess',
                                                                )
                                                                .replaceAll(
                                                                  '{count}',
                                                                  count
                                                                      .toString(),
                                                                ),
                                                          );
                                                          setState(() {
                                                            _detailsFuture = ref
                                                                .read(
                                                                  appManagementServiceProvider,
                                                                )
                                                                .getPackageDetailedInfo(
                                                                  deviceId,
                                                                  packageName,
                                                                );
                                                          });
                                                        } else {
                                                          _showSnack(
                                                            context,
                                                            context.l10n.t(
                                                              'revokeAllPermissionsNone',
                                                            ),
                                                            isError: true,
                                                          );
                                                        }
                                                      }
                                                    : null,
                                              ),
                                              _AppActionButtonCard(
                                                icon: CupertinoIcons.settings,
                                                title: "系统设置",
                                                description:
                                                    "在设备中打开此应用系统设置详情页",
                                                iconColor: const Color(
                                                  0xFF546E7A,
                                                ),
                                                onPressed: isOnline
                                                    ? () => _runAdbAction(
                                                        context,
                                                        ref,
                                                        service.openAppInfo(
                                                          deviceId,
                                                          packageName,
                                                          isHarmony: isHarmony,
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                              _AppActionButtonCard(
                                                icon: CupertinoIcons
                                                    .cloud_download,
                                                title: "导出 APK",
                                                description:
                                                    "提取并保存 APK 安装包到本地电脑",
                                                iconColor: const Color(
                                                  0xFF3949AB,
                                                ),
                                                onPressed: isOnline
                                                    ? () async {
                                                        final directory =
                                                            await getDirectoryPath();
                                                        if (directory ==
                                                                null ||
                                                            !context
                                                                .mounted) {
                                                          return;
                                                        }
                                                        final safeLabel = package
                                                            .displayName
                                                            .replaceAll(
                                                              RegExp(
                                                                r'[\\/:*?"<>|]',
                                                              ),
                                                              '_',
                                                            );
                                                        final versionStr =
                                                            package.versionName !=
                                                                null
                                                            ? '_v${package.versionName}'
                                                            : '';
                                                        final fileName =
                                                            '$safeLabel$versionStr.apk';
                                                        final localSavePath =
                                                            '$directory/$fileName';
                                                        _showSnack(
                                                          context,
                                                          context.l10n.t(
                                                            'exporting',
                                                          ),
                                                        );
                                                        final result = await service
                                                            .exportApk(
                                                              deviceId,
                                                              packageName,
                                                              localSavePath,
                                                              apkPath: package
                                                                  .apkPath,
                                                            );
                                                        if (context.mounted) {
                                                          final successMsg = context
                                                              .l10n
                                                              .t(
                                                                'exportSuccess',
                                                              )
                                                              .replaceAll(
                                                                '{path}',
                                                                localSavePath,
                                                              );
                                                          final failMsg = context
                                                              .l10n
                                                              .t(
                                                                'exportFailed',
                                                              )
                                                              .replaceAll(
                                                                '{error}',
                                                                result
                                                                    .message,
                                                              );
                                                          _showSnack(
                                                            context,
                                                            result.isSuccess
                                                                ? successMsg
                                                                : failMsg,
                                                            isError: !result
                                                                .isSuccess,
                                                          );
                                                        }
                                                      }
                                                    : null,
                                              ),
                                              _AppActionButtonCard(
                                                icon:
                                                    CupertinoIcons.archivebox,
                                                title: "备份数据",
                                                description: "备份此应用的数据到本地电脑",
                                                iconColor: const Color(
                                                  0xFF5E35B1,
                                                ),
                                                onPressed: isOnline
                                                    ? () => _backupAppData(
                                                        context,
                                                        ref,
                                                        deviceId,
                                                        package,
                                                      )
                                                    : null,
                                              ),
                                              _AppActionButtonCard(
                                                icon: Icons.restore,
                                                title: "恢复数据",
                                                description: "从备份文件中恢复应用的数据",
                                                iconColor: const Color(
                                                  0xFF039BE5,
                                                ),
                                                onPressed: isOnline
                                                    ? () => _restoreAppData(
                                                        context,
                                                        ref,
                                                        deviceId,
                                                        package,
                                                      )
                                                    : null,
                                              ),
                                              _AppActionButtonCard(
                                                icon: CupertinoIcons.trash,
                                                title: "卸载应用",
                                                description: "从设备中彻底卸载并删除此应用",
                                                iconColor: const Color(
                                                  0xFFE53935,
                                                ),
                                                onPressed: isOnline
                                                    ? () async {
                                                        final confirmed =
                                                            await _confirm(
                                                              context,
                                                              context.l10n
                                                                  .t(
                                                                    'uninstallPackage',
                                                                  )
                                                                  .replaceAll(
                                                                    '{package}',
                                                                    packageName,
                                                                  ),
                                                            );
                                                        if (confirmed &&
                                                            context.mounted) {
                                                          final result =
                                                              await service
                                                                  .uninstall(
                                                                    deviceId,
                                                                    packageName,
                                                                    isHarmony: isHarmony,
                                                                  );
                                                          if (context
                                                              .mounted) {
                                                            _showSnack(
                                                              context,
                                                              result.message,
                                                              isError: !result
                                                                  .isSuccess,
                                                            );
                                                          }
                                                          if (result
                                                              .isSuccess) {
                                                            await ref
                                                                .read(
                                                                  packagesProvider(
                                                                    deviceId,
                                                                  ).notifier,
                                                                )
                                                                .refreshSinglePackage(
                                                                  packageName,
                                                                );
                                                          }
                                                        }
                                                      }
                                                    : null,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    _LibsTab(
                                      libs: detail.libs,
                                      extractNativeLibs:
                                          detail.extractNativeLibs,
                                    ),
                                    _ComponentsTab(
                                      components: detail.services,
                                      hintText: '搜索服务 (Service)...',
                                    ),
                                    _ComponentsTab(
                                      components: detail.activities,
                                      hintText: '搜索活动 (Activity)...',
                                    ),
                                    _ComponentsTab(
                                      components: detail.receivers,
                                      hintText:
                                          '搜索广播接收器 (Broadcast Receiver)...',
                                    ),
                                    _ComponentsTab(
                                      components: detail.providers,
                                      hintText:
                                          '搜索内容提供者 (Content Provider)...',
                                      isProvider: true,
                                    ),
                                    _PermissionsTab(
                                      deviceId: widget.deviceId,
                                      packageName: package.name,
                                      permissions: detail.permissions,
                                    ),
                                    _MetadataTab(metadata: detail.metadata),
                                    _DexTab(dexFiles: detail.dexFiles),
                                    _SignatureTab(
                                      signatureMd5: detail.signatureMd5,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );

                    if (useHorizontalLayout) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          summaryCard,
                          const SizedBox(width: 24),
                          tabbedContent,
                          const SizedBox(width: 24),
                        ],
                      );
                    } else {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          summaryCard,
                          const SizedBox(height: 24),
                          tabbedContent,
                        ],
                      );
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AppDetailSummaryCard extends ConsumerStatefulWidget {
  const _AppDetailSummaryCard({
    required this.deviceId,
    required this.package,
    required this.cardBg,
    required this.isDark,
    required this.useHorizontalLayout,
    this.detail,
  });

  final String deviceId;
  final AdbPackage package;
  final Color cardBg;
  final bool isDark;
  final bool useHorizontalLayout;
  final AdbPackageDetail? detail;

  @override
  ConsumerState<_AppDetailSummaryCard> createState() =>
      _AppDetailSummaryCardState();
}

class _AppDetailSummaryCardState extends ConsumerState<_AppDetailSummaryCard> {
  Future<String?>? _packerFuture;
  String? _apkPath;

  @override
  void initState() {
    super.initState();
    _apkPath = widget.package.apkPath;
    _initPackerDetection();
    _fetchApkPathIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _AppDetailSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.detail != oldWidget.detail) {
      _initPackerDetection();
    }
    if (widget.package != oldWidget.package ||
        widget.deviceId != oldWidget.deviceId) {
      _apkPath = widget.package.apkPath;
      _fetchApkPathIfNeeded();
    }
  }

  void _fetchApkPathIfNeeded() {
    if (_apkPath != null && _apkPath!.isNotEmpty) return;
    ref
        .read(appManagementServiceProvider)
        .packagePath(widget.deviceId, widget.package.name)
        .then((res) {
      if (res.isSuccess && mounted) {
        final line = res.stdout.split('\n').firstWhere(
          (l) => l.trim().startsWith('package:'),
          orElse: () => '',
        );
        if (line.isNotEmpty) {
          setState(() {
            _apkPath = line.trim().substring('package:'.length).trim();
          });
        }
      }
    }).catchError((_) {});
  }

  void _initPackerDetection() {
    if (widget.detail != null) {
      _packerFuture = _detectPacker(widget.detail!);
    } else {
      _packerFuture = null;
    }
  }

  Future<String?> _detectPacker(AdbPackageDetail detail) async {
    // 1. 尝试通过本地 rules.db 查询 (最全面的社区特征数据库)
    try {
      final docDir = await getApplicationSupportDirectory();
      final dbFile = File('${docDir.path}/rules.db');

      if (!dbFile.existsSync()) {
        final data = await rootBundle.load('assets/rules/rules.db');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await dbFile.writeAsBytes(bytes);
      }

      final db = sqlite3.open(dbFile.path);
      try {
        for (final libEntry in detail.libs) {
          final libName = libEntry.split(':')[0];
          final results = db.select(
            'SELECT label FROM rules_table WHERE name = ? AND type = 0 LIMIT 1',
            [libName],
          );
          if (results.isNotEmpty) {
            final label = results.first['label'] as String?;
            if (label != null && label.isNotEmpty) {
              final lowerLabel = label.toLowerCase();
              if (lowerLabel.contains('加固') ||
                  lowerLabel.contains('安全') ||
                  lowerLabel.contains('易盾') ||
                  lowerLabel.contains('乐固') ||
                  lowerLabel.contains('御安全') ||
                  lowerLabel.contains('爱加密')) {
                return label;
              }
            }
          }
        }
      } finally {
        db.dispose();
      }
    } catch (e) {
      print('加固检测查询数据库失败: $e');
    }

    // 2. 数据库未查到或失败，执行本地规则匹配（兜底，包含常见加固 .so 文件）
    for (final libEntry in detail.libs) {
      final libName = libEntry.split(':')[0].toLowerCase();

      if (libName.contains('jiagu') || libName.contains('x86bridge')) {
        return '360加固';
      }
      if (libName.contains('secshell') || 
          libName.contains('sec.so') || 
          libName.contains('secexe.so') || 
          libName.contains('dexjni') || 
          libName.contains('dexhelper')) {
        return '梆梆加固';
      }
      if (libName.contains('baiduprotect')) {
        return '百度加固';
      }
      if (libName.contains('nesec') || libName.contains('netsecsdk') || libName.contains('netmobsec') || libName.contains('nethtprotect')) {
        return '网易易盾';
      }
      if (libName.contains('ijm') || libName.contains('exec.so') || libName.contains('execmain') || libName.contains('execoat')) {
        return '爱加密';
      }
      if (libName.contains('chaosvmp') || libName.contains('ddog.so') || libName.contains('edog.so') || libName.contains('fdog.so') || libName.contains('hdog.so') || libName.contains('vdog.so') || libName.contains('xloader.so')) {
        return '娜迦加固';
      }
      if (libName.contains('x3g.so')) {
        return '顶象加固';
      }
      if (libName.contains('basec.so') || libName.contains('secenh')) {
        return 'CFCA 加固';
      }
      if (libName.contains('apkprotect')) {
        return 'APKProtect加固';
      }
      if (libName.contains('ros.so') || libName.contains('vfs.so')) {
        return '深思数盾加固';
      }
      if (libName.contains('sgmain') || libName.contains('sgsecuritybody') || libName.contains('mobisec') || libName.contains('stee.so')) {
        return '阿里聚安全';
      }
      if (libName.contains('shell-super') || libName.contains('shella.so') || libName.contains('shellx.so') || libName.contains('tup.so') || libName.contains('txc.so') || libName.contains('turing.so') || libName.contains('pyc.so')) {
        return '腾讯御安全 / 腾讯乐固';
      }
    }

    // 3. 检查组件类名 (以防 native 库没有提取成功，或无 so 纯 DEX 壳的情况)
    final allComponents = [
      ...detail.activities,
      ...detail.services,
      ...detail.receivers,
      ...detail.providers,
    ];

    for (final comp in allComponents) {
      final name = comp.name;
      if (name.contains('com.stub.StubApp')) {
        return '360加固';
      }
      if (name.contains('com.secshell.')) {
        return '梆梆加固';
      }
      if (name.contains('com.tencent.StubShell.')) {
        return '腾讯乐固';
      }
      if (name.contains('com.baidu.protect.')) {
        return '百度加固';
      }
      if (name.contains('com.ali.mobisecwrapper.')) {
        return '阿里聚安全';
      }
      if (name.contains('com.ijiami.')) {
        return '爱加密';
      }
      if (name.contains('com.netease.nis.')) {
        return '网易易盾';
      }
      if (name.contains('com.sangfor.protect.')) {
        return '深信服加固';
      }
      if (name.contains('com.apkprotect.')) {
        return 'APKProtect加固';
      }
    }

    // 4. 检查是否有未识别但符合加固常见命名特征的 .so 库 (标记为未知加固)
    for (final libEntry in detail.libs) {
      final libName = libEntry.split(':')[0].toLowerCase();
      if (libName.contains('protect') ||
          libName.contains('guard') ||
          libName.contains('stub') ||
          libName.contains('dexshell') ||
          libName.contains('shield')) {
        return '未知加固';
      }
    }

    // 5. 检查是否有未识别但符合加固外壳常见命名特征的类名
    for (final comp in allComponents) {
      final name = comp.name.toLowerCase();
      if (name.contains('wrapperapplication') ||
          name.contains('stubapplication') ||
          name.contains('superapplication') ||
          name.contains('applicationwrapper')) {
        return '未知加固';
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final iconPath = widget.package.iconLocalPath;

    return Container(
      decoration: BoxDecoration(
        color: widget.cardBg,
        border: Border(
          right: widget.useHorizontalLayout
              ? BorderSide(
                  color: widget.isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.04),
                  width: 1,
                )
              : BorderSide.none,
          bottom: widget.useHorizontalLayout
              ? BorderSide.none
              : BorderSide(
                  color: widget.isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.04),
                  width: 1,
                ),
        ),
      ),
      padding: const EdgeInsets.all(15),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: iconPath != null && File(iconPath).existsSync()
                          ? Image.file(
                              File(iconPath),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  _FallbackIconLarge(
                                    package: widget.package,
                                    theme: theme,
                                  ),
                            )
                          : _FallbackIconLarge(package: widget.package, theme: theme),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.package.displayName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.package.versionLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.8,
                      ),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.detail != null) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      alignment: WrapAlignment.center,
                      children: [
                        if (widget.detail!.supportedAbis.isNotEmpty)
                          _Badge(
                            label: widget.detail!.supportedAbis.join(', '),
                            color: Colors.blue.shade50,
                            textColor: Colors.blue.shade800,
                          ),
                        for (final fw in widget.detail!.frameworks)
                          _Badge(
                            label: fw,
                            color: Colors.green.shade50,
                            textColor: Colors.green.shade800,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            _SummaryItem(label: "包名", value: widget.package.name, canCopy: true),
            _SummaryItem(
              label: "最低支持系统版本",
              value: AndroidVersionHelper.formatApiLevel(widget.package.minSdk),
            ),
            _SummaryItem(
              label: "目标系统版本",
              value: AndroidVersionHelper.formatApiLevel(widget.package.targetSdk),
            ),
            if (widget.package.maxSdk != null)
              _SummaryItem(
                label: "最大支持系统版本",
                value: AndroidVersionHelper.formatApiLevel(widget.package.maxSdk),
              ),
            _SummaryItem(
              label: "安装时间",
              value: (() {
                final ms = widget.package.firstInstallTime;
                if (ms == null || ms <= 0) return '-';
                final dt = DateTime.fromMillisecondsSinceEpoch(ms);
                return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
              })(),
            ),
            _SummaryItem(
              label: "更新时间",
              value: (() {
                final ms = widget.package.lastUpdateTime;
                if (ms == null || ms <= 0) return '-';
                final dt = DateTime.fromMillisecondsSinceEpoch(ms);
                return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
              })(),
            ),
            _SummaryItem(label: "安装大小", value: widget.package.storageLabel),
            _SummaryItem(
              label: "类型",
              value:
                  "${widget.package.system ? '系统应用' : '用户应用'} / ${widget.package.flutter ? 'Flutter' : '原生'}",
            ),
            _SummaryItem(
              label: "状态",
              value: widget.package.enabled ? "已启用" : "已停用",
              valueColor: widget.package.enabled
                  ? const Color(0xFF2EC46B)
                  : const Color(0xFFE53935),
            ),
            if (widget.package.debuggable)
              _SummaryItem(
                label: "调试模式",
                value: "DEBUG",
                valueColor: colorScheme.error,
              ),
            if (_packerFuture != null)
              FutureBuilder<String?>(
                future: _packerFuture,
                builder: (context, snapshot) {
                  final packer = snapshot.data;
                  if (packer != null) {
                    return _SummaryItem(
                      label: "加固状态",
                      value: packer,
                      valueColor: Colors.orange.shade700,
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            if (_apkPath != null && _apkPath!.isNotEmpty)
              _SummaryItem(
                label: "文件路径",
                value: _apkPath!,
                canCopy: true,
                maxLines: 4,
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    this.canCopy = false,
    this.valueColor,
    this.maxLines = 2,
  });

  final String label;
  final String value;
  final bool canCopy;
  final Color? valueColor;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Tooltip(
                  message: value,
                  waitDuration: const Duration(milliseconds: 500),
                  child: Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: valueColor,
                    ),
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (canCopy) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    _showSnack(context, '$label已复制到剪贴板');
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  splashRadius: 16,
                  tooltip: '复制$label',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AppActionButtonCard extends StatelessWidget {
  const _AppActionButtonCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.iconColor,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color iconColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color cardBg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.white.withValues(alpha: 0.5);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cardBg,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
