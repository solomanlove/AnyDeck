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

    final Color cardBg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.white.withValues(alpha: 0.5);

    final titleColor = isDark ? const Color(0xffeceff1) : const Color(0xff202124);

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
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.03),
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
                onPressed: isOnline ? () async {
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
                            .getPackageDetailedInfo(deviceId, packageName);
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
                } : null,
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
              final isLoading = snapshot.connectionState == ConnectionState.waiting;
              final error = snapshot.error;

              return DefaultTabController(
                length: 10,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final useHorizontalLayout = constraints.maxWidth >= 720;

                      final summaryCard = SizedBox(
                        width: useHorizontalLayout ? 300 : double.infinity,
                        child: _AppDetailSummaryCard(
                          package: package,
                          cardBg: cardBg,
                          isDark: isDark,
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
                                Tab(text: '原生库${detail != null ? ' (${detail.libs.length})' : ''}'),
                                Tab(text: '服务${detail != null ? ' (${detail.services.length})' : ''}'),
                                Tab(text: '活动${detail != null ? ' (${detail.activities.length})' : ''}'),
                                Tab(text: '广播接收器${detail != null ? ' (${detail.receivers.length})' : ''}'),
                                Tab(text: '内容提供者${detail != null ? ' (${detail.providers.length})' : ''}'),
                                Tab(text: '权限${detail != null ? ' (${detail.permissions.length})' : ''}'),
                                Tab(text: '元数据${detail != null ? ' (${detail.metadata.length})' : ''}'),
                                Tab(text: 'DEX${detail != null ? ' (${detail.dexFiles.length})' : ''}'),
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
                                        mainAxisAlignment: MainAxisAlignment.center,
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
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(CupertinoIcons.exclamationmark_triangle, color: Colors.orange, size: 40),
                                          const SizedBox(height: 12),
                                          Text('分析失败: ${error ?? '无数据'}'),
                                          const SizedBox(height: 12),
                                          ElevatedButton(
                                            onPressed: () {
                                              setState(() {
                                                _detailsFuture = ref
                                                    .read(appManagementServiceProvider)
                                                    .getPackageDetailedInfo(widget.deviceId, widget.package.name);
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
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Text(
                                              "功能操作",
                                              style: theme.textTheme.titleMedium?.copyWith(
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
                                              physics: const NeverScrollableScrollPhysics(),
                                              children: [
                                                _AppActionButtonCard(
                                                  icon: CupertinoIcons.play,
                                                  title: "启动应用",
                                                  description: "运行并启动此应用的主界面",
                                                  iconColor: const Color(0xFF2EC46B),
                                                  onPressed: isOnline ? () => _runAdbAction(
                                                    context,
                                                    ref,
                                                    service.launch(deviceId, packageName),
                                                  ) : null,
                                                ),
                                                _AppActionButtonCard(
                                                  icon: CupertinoIcons.stop,
                                                  title: "强行停止",
                                                  description: "强行关闭此应用的所有后台进程",
                                                  iconColor: const Color(0xFFE53935),
                                                  onPressed: isOnline ? () => _runAdbAction(
                                                    context,
                                                    ref,
                                                    service.forceStop(deviceId, packageName),
                                                  ) : null,
                                                ),
                                                _AppActionButtonCard(
                                                  icon: CupertinoIcons.clear,
                                                  title: "清除数据",
                                                  description: "清除所有应用数据及缓存",
                                                  iconColor: const Color(0xFFFB8C00),
                                                  onPressed: isOnline ? () async {
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
                                                  } : null,
                                                ),
                                                _AppActionButtonCard(
                                                  icon: package.enabled ? CupertinoIcons.snow : CupertinoIcons.flame,
                                                  title: package.enabled ? "冻结应用" : "解冻应用",
                                                  description: package.enabled ? "禁用并隐藏此应用" : "恢复并启用此应用",
                                                  iconColor: const Color(0xFF0288D1),
                                                  onPressed: isOnline ? () async {
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
                                                        await ref
                                                            .read(packagesProvider(deviceId).notifier)
                                                            .refreshSinglePackage(packageName);
                                                      }
                                                    }
                                                  } : null,
                                                ),
                                                _AppActionButtonCard(
                                                  icon: Icons.cast,
                                                  title: "应用投屏",
                                                  description: "在虚拟副屏中开启此应用投屏",
                                                  iconColor: const Color(0xFF8E24AA),
                                                  onPressed: isOnline ? () async {
                                                    final windowTitle = context.l10n
                                                        .t('screenMirrorTitle')
                                                        .replaceAll('{name}', package.displayName);
                                                    final textureId = ref.read(activeEmbeddedMirrorProvider(deviceId));
                                                    if (textureId != null) {
                                                      await ref.read(activeEmbeddedMirrorProvider(deviceId).notifier).forceStop();
                                                    }
                                                    try {
                                                      final overviewAsync = ref.read(deviceOverviewProvider(deviceId));
                                                      final resolution = overviewAsync.maybeWhen(
                                                        data: (overview) => overview.physicalResolution,
                                                        orElse: () => null,
                                                      );
                                                      String vdResolution = '1080x1920';
                                                      if (resolution != null && resolution.contains('x')) {
                                                        final parts = resolution.split('x');
                                                        if (parts.length == 2) {
                                                          final w = int.tryParse(parts[0].trim());
                                                          final h = int.tryParse(parts[1].trim());
                                                          if (w != null && h != null) {
                                                            final minSide = w < h ? w : h;
                                                            final maxSide = w > h ? w : h;
                                                            double scale = 1.0;
                                                            if (maxSide > 1920) {
                                                              scale = 1920 / maxSide;
                                                            }
                                                            final targetW = ((minSide * scale).toInt() ~/ 2) * 2;
                                                            final targetH = ((maxSide * scale).toInt() ~/ 2) * 2;
                                                            vdResolution = '${targetW}x$targetH';
                                                          }
                                                        }
                                                      }
                                                      final initialSize = _resolveMirrorInitialWindowSize(vdResolution);
                                                      await createAdbManageWindow(
                                                        arguments: {
                                                          'type': 'mirror',
                                                          'deviceId': deviceId,
                                                          'deviceName': package.displayName,
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
                                                  } : null,
                                                ),
                                                _AppActionButtonCard(
                                                  icon: CupertinoIcons.shield,
                                                  title: "权限管理",
                                                  description: "查看并更改应用被授予的权限",
                                                  iconColor: const Color(0xFF43A047),
                                                  onPressed: isOnline ? () {
                                                    DefaultTabController.of(context).animateTo(6);
                                                  } : null,
                                                ),
                                                _AppActionButtonCard(
                                                  icon: CupertinoIcons.lock_open,
                                                  title: "重置权限",
                                                  description: "撤销当前应用的所有运行时权限",
                                                  iconColor: const Color(0xFFD81B60),
                                                  onPressed: isOnline ? () async {
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
                                                      setState(() {
                                                        _detailsFuture = ref
                                                            .read(appManagementServiceProvider)
                                                            .getPackageDetailedInfo(deviceId, packageName);
                                                      });
                                                    } else {
                                                      _showSnack(
                                                        context,
                                                        context.l10n.t('revokeAllPermissionsNone'),
                                                        isError: true,
                                                      );
                                                    }
                                                  } : null,
                                                ),
                                                _AppActionButtonCard(
                                                  icon: CupertinoIcons.settings,
                                                  title: "系统设置",
                                                  description: "在设备中打开此应用系统设置详情页",
                                                  iconColor: const Color(0xFF546E7A),
                                                  onPressed: isOnline ? () => _runAdbAction(
                                                    context,
                                                    ref,
                                                    service.openAppInfo(deviceId, packageName),
                                                  ) : null,
                                                ),
                                                _AppActionButtonCard(
                                                  icon: CupertinoIcons.arrow_merge,
                                                  title: "安装路径",
                                                  description: "显示 APK 在设备中的存储路径",
                                                  iconColor: const Color(0xFF00ACC1),
                                                  onPressed: isOnline ? () => _showAdbResult(
                                                    context,
                                                    ref,
                                                    service.packagePath(deviceId, packageName),
                                                  ) : null,
                                                ),
                                                _AppActionButtonCard(
                                                  icon: CupertinoIcons.cloud_download,
                                                  title: "导出 APK",
                                                  description: "提取并保存 APK 安装包到本地电脑",
                                                  iconColor: const Color(0xFF3949AB),
                                                  onPressed: isOnline ? () async {
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
                                                  } : null,
                                                ),
                                                _AppActionButtonCard(
                                                  icon: CupertinoIcons.archivebox,
                                                  title: "备份数据",
                                                  description: "备份此应用的数据到本地电脑",
                                                  iconColor: const Color(0xFF5E35B1),
                                                  onPressed: isOnline ? () => _backupAppData(context, ref, deviceId, package) : null,
                                                ),
                                                _AppActionButtonCard(
                                                  icon: Icons.restore,
                                                  title: "恢复数据",
                                                  description: "从备份文件中恢复应用的数据",
                                                  iconColor: const Color(0xFF039BE5),
                                                  onPressed: isOnline ? () => _restoreAppData(context, ref, deviceId, package) : null,
                                                ),
                                                _AppActionButtonCard(
                                                  icon: CupertinoIcons.trash,
                                                  title: "卸载应用",
                                                  description: "从设备中彻底卸载并删除此应用",
                                                  iconColor: const Color(0xFFE53935),
                                                  onPressed: isOnline ? () async {
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
                                                        await ref
                                                            .read(packagesProvider(deviceId).notifier)
                                                            .refreshSinglePackage(packageName);
                                                      }
                                                    }
                                                  } : null,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      _LibsTab(libs: detail.libs),
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
                                        hintText: '搜索广播接收器 (Broadcast Receiver)...',
                                      ),
                                      _ComponentsTab(
                                        components: detail.providers,
                                        hintText: '搜索内容提供者 (Content Provider)...',
                                        isProvider: true,
                                      ),
                                      _PermissionsTab(
                                        deviceId: widget.deviceId,
                                        packageName: package.name,
                                        permissions: detail.permissions,
                                      ),
                                      _MetadataTab(metadata: detail.metadata),
                                      _DexTab(dexFiles: detail.dexFiles),
                                      _SignatureTab(signatureMd5: detail.signatureMd5),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            summaryCard,
                            const SizedBox(width: 24),
                            tabbedContent,
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
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AppDetailSummaryCard extends StatelessWidget {
  const _AppDetailSummaryCard({
    required this.package,
    required this.cardBg,
    required this.isDark,
    this.detail,
  });

  final AdbPackage package;
  final Color cardBg;
  final bool isDark;
  final AdbPackageDetail? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final iconPath = package.iconLocalPath;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(24),
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
                                _FallbackIconLarge(package: package, theme: theme),
                          )
                        : _FallbackIconLarge(package: package, theme: theme),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  package.displayName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  package.versionLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                  textAlign: TextAlign.center,
                ),
                if (detail != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: [
                      if (detail!.supportedAbis.isNotEmpty)
                        _Badge(
                          label: detail!.supportedAbis.join(', '),
                          color: Colors.blue.shade50,
                          textColor: Colors.blue.shade800,
                        ),
                      for (final fw in detail!.frameworks)
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
          
          _SummaryItem(
            label: "包名",
            value: package.name,
            canCopy: true,
          ),
          _SummaryItem(
            label: "安装大小",
            value: package.storageLabel,
          ),
          _SummaryItem(
            label: "类型",
            value: "${package.system ? '系统应用' : '用户应用'} / ${package.flutter ? 'Flutter' : '原生'}",
          ),
          _SummaryItem(
            label: "状态",
            value: package.enabled ? "已启用" : "已停用",
            valueColor: package.enabled ? const Color(0xFF2EC46B) : const Color(0xFFE53935),
          ),
          if (package.debuggable)
            _SummaryItem(
              label: "调试模式",
              value: "DEBUG",
              valueColor: colorScheme.error,
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
  });

  final String label;
  final String value;
  final bool canCopy;
  final Color? valueColor;

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
            children: [
              Expanded(
                child: Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: valueColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (canCopy)
                IconButton(
                  icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    _showSnack(context, '包名已复制到剪贴板');
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 16,
                  tooltip: '复制包名',
                ),
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
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
