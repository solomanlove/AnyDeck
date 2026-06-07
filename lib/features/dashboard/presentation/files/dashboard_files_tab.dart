part of '../dashboard_screen.dart';

class _FilesTab extends ConsumerWidget {
  const _FilesTab({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(fileNavigationProvider);
    final path = navState.currentPath;
    final request = RemoteDirectoryRequest(deviceId: device.id, path: path);
    final filesAsync = ref.watch(remoteFilesProvider(request));
    final filterQuery = ref.watch(fileFilterQueryProvider);

    return DropTarget(
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
                  onPressed: path != '/'
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
                                      children: _buildBreadcrumbs(
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
                SizedBox(
                  width: 150,
                  height: 38,
                  child: TextField(
                    onChanged: (val) => ref
                        .read(fileFilterQueryProvider.notifier)
                        .setQuery(val),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        CupertinoIcons.line_horizontal_3_decrease,
                        size: 16,
                      ),
                      hintText: context.l10n.t('filter'),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
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
                  tooltip: navState.showHiddenFiles ? '隐藏隐藏文件' : '显示隐藏文件',
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
                const _FileSortMenuButton(),
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
            // Table Header (only visible in list view)
            if (!navState.isGridView) _buildTableHeader(context, ref),
            // Files List / Grid / Table Rows
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
                  // Client-side filtering
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

                  // Client-side sorting
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
                    return GridView.builder(
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
                          onTap: () {
                            if (file.isFolder) {
                              ref
                                  .read(fileNavigationProvider.notifier)
                                  .navigateTo(_joinRemotePath(path, file.name));
                            } else if (_isPreviewableTextFile(file.name)) {
                              _previewTextFile(
                                context,
                                ref,
                                device.id,
                                path,
                                file,
                              );
                            }
                          },
                        );
                      },
                    );
                  }

                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final file = filtered[index];
                      return _FileRow(
                        file: file,
                        deviceId: device.id,
                        currentPath: path,
                        onTap: () {
                          if (file.isFolder) {
                            ref
                                .read(fileNavigationProvider.notifier)
                                .navigateTo(_joinRemotePath(path, file.name));
                          } else if (_isPreviewableTextFile(file.name)) {
                            _previewTextFile(
                              context,
                              ref,
                              device.id,
                              path,
                              file,
                            );
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBreadcrumbs(
    BuildContext context,
    WidgetRef ref,
    String path,
  ) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final list = <Widget>[];

    // Root segment
    list.add(
      TextButton(
        onPressed: () {
          ref.read(fileNavigationProvider.notifier).navigateTo('/');
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          context.l10n.t('storage'),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );

    var currentAccPath = '/';
    for (final segment in segments) {
      list.add(
        Text(
          ' > ',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      );
      currentAccPath += '$segment/';
      final segmentPath = currentAccPath;
      list.add(
        TextButton(
          onPressed: () {
            ref.read(fileNavigationProvider.notifier).navigateTo(segmentPath);
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            segment,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return list;
  }

  /// 上传拖入或选中的文件；APK 会执行安装而不是复制。
  Future<void> _pushFiles(
    BuildContext context,
    WidgetRef ref,
    List<XFile> files,
    String remotePath,
  ) async {
    final service = ref.read(fileManagerServiceProvider);
    final appService = ref.read(appManagementServiceProvider);
    final transferNotifier = ref.read(transferListProvider.notifier);

    for (final file in files) {
      final isApk = file.path.toLowerCase().endsWith('.apk');
      final taskId = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      transferNotifier.addTask(
        TransferTask(
          id: taskId,
          name: file.name,
          deviceId: device.id,
          isApk: isApk,
        ),
      );

      try {
        final result = isApk
            ? await appService.installApk(device.id, file.path)
            : await service.push(device.id, file.path, remotePath);

        transferNotifier.updateTask(
          id: taskId,
          isDone: true,
          isSuccess: result.isSuccess,
          error: result.isSuccess ? null : result.message,
        );

        if (!context.mounted) {
          return;
        }

        final message = isApk
            ? (result.isSuccess
                  ? context.l10n
                        .t('apkInstallSuccess')
                        .replaceAll('{name}', file.name)
                  : context.l10n
                        .t('apkInstallFailed')
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
