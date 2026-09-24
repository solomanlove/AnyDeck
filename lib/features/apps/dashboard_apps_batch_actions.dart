part of '../dashboard_screen.dart';

/// 批量应用操作进度模型。
class _BatchProgressState {
  const _BatchProgressState({
    required this.title,
    required this.current,
    required this.total,
    required this.currentName,
  });

  final String title;
  final int current;
  final int total;
  final String currentName;

  double get progress => total == 0 ? 0.0 : current / total;
}

/// 批量操作进度卡片（仅限制在当前 Tab 区域内展示，避免弹窗遮挡侧边导航）。
class _AppsBatchProgressCard extends StatelessWidget {
  const _AppsBatchProgressCard({
    required this.state,
  });

  final _BatchProgressState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 380,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: theme.dialogTheme.backgroundColor ?? colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.progress,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    state.currentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${state.current}/${state.total}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 批量应用操作工具栏。
/// 当用户在列表中勾选一个或多个应用时展示，提供批量导出、批量卸载、批量清除数据、批量冻结/解冻等操作。
class _AppsBatchActionsToolbar extends ConsumerWidget {
  const _AppsBatchActionsToolbar({
    required this.deviceId,
    required this.checkedPackages,
    required this.allFilteredPackages,
    required this.progressNotifier,
    required this.onClearSelection,
    required this.onSelectAll,
    required this.isHarmony,
  });

  final String deviceId;
  final Set<String> checkedPackages;
  final List<AdbPackage> allFilteredPackages;
  final ValueNotifier<_BatchProgressState?> progressNotifier;
  final VoidCallback onClearSelection;
  final VoidCallback onSelectAll;
  final bool isHarmony;

  List<AdbPackage> _getSelectedPackageModels() => allFilteredPackages
      .where((pkg) => checkedPackages.contains(pkg.name))
      .toList(growable: false);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isOnline = ref.watch(deviceOnlineProvider(deviceId));
    final count = checkedPackages.length;
    final isAllSelected =
        allFilteredPackages.isNotEmpty && count == allFilteredPackages.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.checkmark_circle_fill,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            context.l10n
                .t('batchSelectedCount')
                .replaceAll('{count}', '$count'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          // 全选 / 取消全选快捷切换
          TextButton(
            onPressed: isAllSelected ? onClearSelection : onSelectAll,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              isAllSelected
                  ? context.l10n.t('deselectAll')
                  : context.l10n.t('selectAll'),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            height: 18,
            width: 1,
            color: theme.dividerColor.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 8),
          // 批量操作按钮区域
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // 1. 批量导出包
                  FilledButton.tonalIcon(
                    onPressed: isOnline ? () => _exportPackages(context, ref) : null,
                    icon: const Icon(CupertinoIcons.square_arrow_up, size: 15),
                    label: Text(context.l10n.t('batchExportApk')),
                    style: _buttonStyle(),
                  ),
                  const SizedBox(width: 8),
                  // 2. 批量卸载包
                  FilledButton.tonalIcon(
                    onPressed: isOnline ? () => _uninstallPackages(context, ref) : null,
                    icon: const Icon(CupertinoIcons.trash, size: 15),
                    label: Text(context.l10n.t('batchUninstall')),
                    style: _buttonStyle(
                      backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.4),
                      foregroundColor: colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 3. 批量清除数据
                  FilledButton.tonalIcon(
                    onPressed: isOnline ? () => _clearDataPackages(context, ref) : null,
                    icon: const Icon(CupertinoIcons.clear, size: 15),
                    label: Text(context.l10n.t('batchClearData')),
                    style: _buttonStyle(),
                  ),
                  const SizedBox(width: 8),
                  // 4. 批量冻结应用
                  FilledButton.tonalIcon(
                    onPressed: isOnline ? () => _freezePackages(context, ref) : null,
                    icon: const Icon(CupertinoIcons.snow, size: 15),
                    label: Text(context.l10n.t('batchFreezeApp')),
                    style: _buttonStyle(),
                  ),
                  const SizedBox(width: 8),
                  // 5. 批量解冻应用
                  FilledButton.tonalIcon(
                    onPressed: isOnline ? () => _unfreezePackages(context, ref) : null,
                    icon: const Icon(CupertinoIcons.flame, size: 15),
                    label: Text(context.l10n.t('batchUnfreezeApp')),
                    style: _buttonStyle(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 清除选中按钮
          IconButton(
            tooltip: context.l10n.t('deselectAll'),
            icon: const Icon(CupertinoIcons.xmark, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: onClearSelection,
          ),
        ],
      ),
    );
  }

  ButtonStyle _buttonStyle({Color? backgroundColor, Color? foregroundColor}) {
    return FilledButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      minimumSize: const Size(0, 32),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      visualDensity: VisualDensity.compact,
    );
  }

  /// 通用批量任务执行流程，自动通过 progressNotifier 在当前 Tab 内更新进度。
  Future<void> _executeBatchTask(
    BuildContext context, {
    required String runningTitle,
    required List<AdbPackage> targets,
    required Future<bool> Function(AdbPackage pkg) processItem,
    required Future<void> Function(int success, int fail) onCompleted,
  }) async {
    progressNotifier.value = _BatchProgressState(
      title: runningTitle,
      current: 0,
      total: targets.length,
      currentName: targets.first.displayName,
    );

    var successCount = 0;
    var failCount = 0;

    for (var i = 0; i < targets.length; i++) {
      final pkg = targets[i];
      progressNotifier.value = _BatchProgressState(
        title: runningTitle,
        current: i + 1,
        total: targets.length,
        currentName: pkg.displayName,
      );

      try {
        final success = await processItem(pkg);
        if (success) {
          successCount++;
        } else {
          failCount++;
        }
      } catch (_) {
        failCount++;
      }
    }

    progressNotifier.value = null;
    if (context.mounted) {
      await onCompleted(successCount, failCount);
    }
  }

  /// 批量导出选中的包到本地指定目录。
  Future<void> _exportPackages(BuildContext context, WidgetRef ref) async {
    final targets = _getSelectedPackageModels();
    if (targets.isEmpty) return;

    final directory = await getDirectoryPath();
    if (directory == null || !context.mounted) return;

    final service = ref.read(appManagementServiceProvider);
    final runningTitle = context.l10n.t('batchExportRunning');

    await _executeBatchTask(
      context,
      runningTitle: runningTitle,
      targets: targets,
      processItem: (pkg) async {
        final safeName = pkg.displayName
            .replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')
            .trim();
        final finalName = safeName.isEmpty ? pkg.name : safeName;
        final versionStr = pkg.versionName != null && pkg.versionName!.isNotEmpty
            ? '_v${pkg.versionName}'
            : '';
        final localSavePath = '$directory/$finalName$versionStr.apk';
        final result = await service.exportApk(
          deviceId,
          pkg.name,
          localSavePath,
          apkPath: pkg.apkPath,
        );
        return result.isSuccess;
      },
      onCompleted: (success, fail) async {
        if (!context.mounted) return;
        final msg = context.l10n
            .t('batchExportSuccess')
            .replaceAll('{success}', '$success')
            .replaceAll('{failed}', '$fail');
        final saveMsg = context.l10n
            .t('batchExportSavePath')
            .replaceAll('{path}', directory);
        _showSnack(context, '$msg\n$saveMsg');
      },
    );
  }

  /// 批量卸载选中的应用。
  Future<void> _uninstallPackages(BuildContext context, WidgetRef ref) async {
    final targets = _getSelectedPackageModels();
    if (targets.isEmpty) return;

    final confirmed = await _confirm(
      context,
      context.l10n
          .t('batchUninstallConfirm')
          .replaceAll('{count}', '${targets.length}'),
    );
    if (!confirmed || !context.mounted) return;

    final service = ref.read(appManagementServiceProvider);
    final runningTitle = context.l10n.t('batchUninstallRunning');
    final successfulUninstalled = <String>{};

    await _executeBatchTask(
      context,
      runningTitle: runningTitle,
      targets: targets,
      processItem: (pkg) async {
        final result = await service.uninstall(
          deviceId,
          pkg.name,
          isHarmony: isHarmony,
        );
        if (result.isSuccess) {
          successfulUninstalled.add(pkg.name);
        }
        return result.isSuccess;
      },
      onCompleted: (success, fail) async {
        if (successfulUninstalled.isNotEmpty) {
          await ref
              .read(packagesProvider(deviceId).notifier)
              .removePackages(successfulUninstalled);
        }
        onClearSelection();
        if (!context.mounted) return;
        final msg = context.l10n
            .t('batchUninstallSuccess')
            .replaceAll('{success}', '$success')
            .replaceAll('{failed}', '$fail');
        _showSnack(context, msg, isError: fail > 0);
      },
    );
  }

  /// 批量清除选中应用的数据。
  Future<void> _clearDataPackages(BuildContext context, WidgetRef ref) async {
    final targets = _getSelectedPackageModels();
    if (targets.isEmpty) return;

    final confirmed = await _confirm(
      context,
      context.l10n
          .t('batchClearDataConfirm')
          .replaceAll('{count}', '${targets.length}'),
    );
    if (!confirmed || !context.mounted) return;

    final service = ref.read(appManagementServiceProvider);
    final runningTitle = context.l10n.t('batchClearDataRunning');

    await _executeBatchTask(
      context,
      runningTitle: runningTitle,
      targets: targets,
      processItem: (pkg) async {
        final result = await service.clearData(
          deviceId,
          pkg.name,
          isHarmony: isHarmony,
        );
        return result.isSuccess;
      },
      onCompleted: (success, fail) async {
        if (!context.mounted) return;
        final msg = context.l10n
            .t('batchClearDataSuccess')
            .replaceAll('{success}', '$success')
            .replaceAll('{failed}', '$fail');
        _showSnack(context, msg, isError: fail > 0);
      },
    );
  }

  /// 批量冻结（停用）选中的应用。
  Future<void> _freezePackages(BuildContext context, WidgetRef ref) =>
      _setFreezeStatus(context, ref, freeze: true);

  /// 批量解冻（启用）选中的应用。
  Future<void> _unfreezePackages(BuildContext context, WidgetRef ref) =>
      _setFreezeStatus(context, ref, freeze: false);

  /// 批量设置应用冻结/解冻状态。
  Future<void> _setFreezeStatus(
    BuildContext context,
    WidgetRef ref, {
    required bool freeze,
  }) async {
    final targets = _getSelectedPackageModels();
    if (targets.isEmpty) return;

    final confirmKey = freeze ? 'batchFreezeConfirm' : 'batchUnfreezeConfirm';
    final confirmed = await _confirm(
      context,
      context.l10n.t(confirmKey).replaceAll('{count}', '${targets.length}'),
    );
    if (!confirmed || !context.mounted) return;

    final service = ref.read(appManagementServiceProvider);
    final notifier = ref.read(packagesProvider(deviceId).notifier);
    final runningTitle = context.l10n.t(
      freeze ? 'batchFreezeRunning' : 'batchUnfreezeRunning',
    );

    await _executeBatchTask(
      context,
      runningTitle: runningTitle,
      targets: targets,
      processItem: (pkg) async {
        final result = freeze
            ? await service.freezeApp(deviceId, pkg.name, isHarmony: isHarmony)
            : await service.unfreezeApp(deviceId, pkg.name, isHarmony: isHarmony);
        if (result.isSuccess) {
          await notifier.refreshSinglePackage(pkg.name);
          return true;
        }
        return false;
      },
      onCompleted: (success, fail) async {
        if (!context.mounted) return;
        final successKey = freeze ? 'batchFreezeSuccess' : 'batchUnfreezeSuccess';
        final msg = context.l10n
            .t(successKey)
            .replaceAll('{success}', '$success')
            .replaceAll('{failed}', '$fail');
        _showSnack(context, msg, isError: fail > 0);
      },
    );
  }
}
