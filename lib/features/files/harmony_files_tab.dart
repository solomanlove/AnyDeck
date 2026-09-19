part of '../dashboard_screen.dart';

/// 鸿蒙手机专属文件管理 Tab。
///
/// 独立文件承载鸿蒙系统的文件浏览与传输逻辑，默认重定向至开发者具备完全读写权限的 `/data/local/tmp/` 目录。
/// 复用公共的文件列表、表格、面包屑导航以及拖拽安装 HAP 机制。
class HarmonyFilesTab extends ConsumerWidget {
  /// 创建鸿蒙专属文件管理 Tab
  const HarmonyFilesTab({super.key, required this.device});

  /// 目标鸿蒙设备
  final AdbDevice device;

  static const String _defaultHarmonyPath = '/data/local/tmp/';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(fileNavigationProvider);

    // 鸿蒙系统根目录通常无权限，默认重定向至开发者读写目录 /data/local/tmp/
    final path = (navState.currentPath == '/' ||
            navState.currentPath.isEmpty ||
            navState.currentPath.startsWith('/storage/emulated/0'))
        ? _defaultHarmonyPath
        : navState.currentPath;

    if (path != navState.currentPath) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(fileNavigationProvider.notifier).navigateTo(_defaultHarmonyPath);
      });
    }

    final request = RemoteDirectoryRequest(deviceId: device.id, path: path);
    final filesAsync = ref.watch(remoteFilesProvider(request));
    final filterQuery = ref.watch(fileFilterQueryProvider);
    final selectedFile = ref.watch(fileSelectionProvider);

    final content = DropTarget(
      onDragDone: (details) => _pushFiles(context, ref, details.files, path),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Toolbar
            Row(
              children: [
                IconButton(
                  tooltip: '后退',
                  icon: const Icon(CupertinoIcons.back),
                  onPressed: navState.canGoBack
                      ? () => ref.read(fileNavigationProvider.notifier).goBack()
                      : null,
                ),
                IconButton(
                  tooltip: '前进',
                  icon: const Icon(CupertinoIcons.forward),
                  onPressed: navState.canGoForward
                      ? () => ref
                            .read(fileNavigationProvider.notifier)
                            .goForward()
                      : null,
                ),
                IconButton(
                  tooltip: '向上',
                  icon: const Icon(CupertinoIcons.up_arrow),
                  onPressed: path != _defaultHarmonyPath && path != '/'
                      ? () => ref.read(fileNavigationProvider.notifier).goUp()
                      : null,
                ),
                IconButton(
                  tooltip: context.l10n.t('refresh'),
                  icon: const Icon(CupertinoIcons.refresh),
                  onPressed: () {
                    ref.invalidate(remoteFilesProvider(request));
                  },
                ),
                ActionChip(
                  avatar: const Icon(CupertinoIcons.folder_badge_person_crop, size: 14),
                  label: const Text('/data/local/tmp/'),
                  onPressed: () {
                    ref.read(fileNavigationProvider.notifier).navigateTo(_defaultHarmonyPath);
                  },
                ),
                const SizedBox(width: 8),
                // Path bar
                Expanded(
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: navState.isEditingPath
                        ? _PathTextField(
                            initialPath: path,
                            onSubmitted: (value) {
                              ref
                                  .read(fileNavigationProvider.notifier)
                                  .navigateTo(value);
                            },
                          )
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: () {
                              ref
                                  .read(fileNavigationProvider.notifier)
                                  .setEditingPath(true);
                            },
                            child: Row(
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: _buildFileBreadcrumbs(
                                        context,
                                        ref,
                                        path,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    CupertinoIcons.pencil,
                                    size: 14,
                                  ),
                                  onPressed: () {
                                    ref
                                        .read(fileNavigationProvider.notifier)
                                        .setEditingPath(true);
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  splashRadius: 16,
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                // Filter search
                const FileHistoryFilterField(),
                const SizedBox(width: 8),
                // View Mode & Hidden Files toggle
                IconButton(
                  tooltip: '网格视图',
                  icon: const Icon(CupertinoIcons.square_grid_2x2, size: 20),
                  isSelected: navState.isGridView,
                  selectedIcon: const Icon(
                    CupertinoIcons.square_grid_2x2_fill,
                    size: 20,
                  ),
                  onPressed: () {
                    ref.read(fileNavigationProvider.notifier).setGridView(true);
                  },
                ),
                IconButton(
                  tooltip: '列表视图',
                  icon: const Icon(CupertinoIcons.list_bullet, size: 20),
                  isSelected: !navState.isGridView,
                  selectedIcon: const Icon(
                    CupertinoIcons.list_bullet,
                    size: 20,
                  ),
                  onPressed: () {
                    ref
                        .read(fileNavigationProvider.notifier)
                        .setGridView(false);
                  },
                ),
                IconButton(
                  tooltip: navState.showHiddenFiles
                      ? context.l10n.t('hideHiddenFiles')
                      : context.l10n.t('showHiddenFiles'),
                  icon: Icon(
                    navState.showHiddenFiles
                        ? CupertinoIcons.eye
                        : CupertinoIcons.eye_slash,
                    size: 20,
                  ),
                  onPressed: () {
                    ref
                        .read(fileNavigationProvider.notifier)
                        .toggleShowHiddenFiles();
                  },
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(CupertinoIcons.cloud_upload),
                  label: Text(context.l10n.t('push')),
                  onPressed: () async {
                    final file = await openFile();
                    if (file != null && context.mounted) {
                      await _pushFiles(context, ref, [file], path);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!navState.isGridView) _buildTableHeader(context, ref),
            Expanded(
              child: filesAsync.when(
                loading: () => _PanelMessage(
                  icon: CupertinoIcons.arrow_2_circlepath,
                  title: context.l10n.t('loadingFiles'),
                  animateIcon: true,
                ),
                error: (error, stackTrace) => _PanelMessage(
                  icon: CupertinoIcons.exclamationmark_circle,
                  title: context.l10n.t('fileListFailed'),
                  subtitle: error.toString(),
                ),
                data: (items) {
                  var filtered = items;
                  if (!navState.showHiddenFiles) {
                    filtered = filtered
                        .where((f) => !f.name.startsWith('.'))
                        .toList();
                  }
                  if (filterQuery.isNotEmpty) {
                    filtered = filtered
                        .where(
                          (f) => f.name.toLowerCase().contains(
                            filterQuery.toLowerCase(),
                          ),
                        )
                        .toList();
                  }

                  filtered = List<RemoteFile>.from(filtered)
                    ..sort(
                      (a, b) => _compareFiles(
                        a,
                        b,
                        navState.sortColumn,
                        navState.sortAscending,
                      ),
                    );

                  if (filtered.isEmpty) {
                    return _PanelMessage(
                      icon: CupertinoIcons.folder_open,
                      title: filterQuery.isNotEmpty
                          ? '未找到匹配的文件'
                          : context.l10n.t('emptyFolder'),
                    );
                  }

                  if (navState.isGridView) {
                    return _FilePreviewShortcut(
                      files: filtered,
                      selectedFile: selectedFile,
                      deviceId: device.id,
                      currentPath: path,
                      child: GridView.builder(
                        padding: const EdgeInsets.only(top: 8),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 110,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.8,
                            ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final file = filtered[index];
                          return _FileGridItem(
                            file: file,
                            deviceId: device.id,
                            currentPath: path,
                            canExportToPhoneFiles: true,
                            selected:
                                selectedFile?.matches(
                                  device.id,
                                  _joinRemotePath(path, file.name),
                                ) ??
                                false,
                            onSelected: () => _selectRemoteFile(
                              ref,
                              device.id,
                              _joinRemotePath(path, file.name),
                            ),
                            onOpened: () => _openRemoteFile(
                              context,
                              ref,
                              device.id,
                              path,
                              file,
                            ),
                          );
                        },
                      ),
                    );
                  }

                  return _FilePreviewShortcut(
                    files: filtered,
                    selectedFile: selectedFile,
                    deviceId: device.id,
                    currentPath: path,
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final file = filtered[index];
                        return _FileRow(
                          index: index,
                          file: file,
                          deviceId: device.id,
                          currentPath: path,
                          canExportToPhoneFiles: true,
                          selected:
                              selectedFile?.matches(
                                device.id,
                                _joinRemotePath(path, file.name),
                              ) ??
                              false,
                          onSelected: () => _selectRemoteFile(
                            ref,
                            device.id,
                            _joinRemotePath(path, file.name),
                          ),
                          onOpened: () => _openRemoteFile(
                            context,
                            ref,
                            device.id,
                            path,
                            file,
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    return _FileQuickAccessLayout(
      deviceId: device.id,
      currentPath: path,
      onSelected: (shortcutPath) => ref
          .read(fileNavigationProvider.notifier)
          .navigateTo(shortcutPath),
      child: Stack(children: [content, const _FilePreviewLoadingOverlay()]),
    );
  }

  /// 上传文件到鸿蒙设备；HAP 文件将自动执行安装，普通文件推送到指定目录。
  Future<void> _pushFiles(
    BuildContext context,
    WidgetRef ref,
    List<XFile> files,
    String remotePath,
  ) async {
    final hdcService = ref.read(hdcServiceProvider);
    final service = ref.read(fileManagerServiceProvider);
    final transferNotifier = ref.read(transferListProvider.notifier);

    for (final file in files) {
      final isHap = file.name.toLowerCase().endsWith('.hap');
      final taskId = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      transferNotifier.addTask(
        TransferTask(
          id: taskId,
          name: file.name,
          deviceId: device.id,
          isApk: false,
        ),
      );

      try {
        final AdbResult result;
        if (isHap) {
          result = await hdcService.installApp(device.id, file.path);
        } else {
          result = await service.push(device.id, file.path, remotePath);
        }

        transferNotifier.updateTask(
          id: taskId,
          isDone: true,
          isSuccess: result.isSuccess,
          error: result.isSuccess ? null : result.message,
        );

        if (!context.mounted) {
          return;
        }

        final message = isHap
            ? (result.isSuccess
                ? context.l10n
                    .t('hapInstallSuccess')
                    .replaceAll('{name}', file.name)
                : context.l10n
                    .t('hapInstallFailed')
                    .replaceAll('{name}', file.name)
                    .replaceAll('{error}', result.message))
            : (result.isSuccess
                ? context.l10n
                    .t('fileUploadSuccess')
                    .replaceAll('{name}', file.name)
                : context.l10n
                    .t('fileUploadFailed')
                    .replaceAll('{name}', file.name)
                    .replaceAll('{error}', result.message));

        _showSnack(context, message, isError: !result.isSuccess);
      } catch (e) {
        transferNotifier.updateTask(
          id: taskId,
          isDone: true,
          isSuccess: false,
          error: e.toString(),
        );
        if (context.mounted) {
          _showSnack(context, '${file.name}: $e', isError: true);
        }
      }
    }
    ref.invalidate(
      remoteFilesProvider(
        RemoteDirectoryRequest(deviceId: device.id, path: remotePath),
      ),
    );
  }
}
