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
                                  icon: const Icon(CupertinoIcons.pencil, size: 14),
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
                  selectedIcon: const Icon(CupertinoIcons.square_grid_2x2_fill, size: 20),
                  onPressed: () {
                    ref.read(fileNavigationProvider.notifier).setGridView(true);
                  },
                ),
                IconButton(
                  tooltip: '列表视图',
                  icon: const Icon(
                    CupertinoIcons.list_bullet,
                    size: 20,
                  ),
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
                    ..sort((a, b) => _compareFiles(a, b, navState.sortColumn, navState.sortAscending));

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
                              _previewTextFile(context, ref, device.id, path, file);
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
                            _previewTextFile(context, ref, device.id, path, file);
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

  Widget _buildTableHeader(BuildContext context, WidgetRef ref) {
    final navState = ref.watch(fileNavigationProvider);
    final notifier = ref.read(fileNavigationProvider.notifier);

    final textStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    Widget buildHeaderCell({
      required String label,
      required String column,
      double? width,
      int? flex,
      bool alignRight = false,
    }) {
      final isSorted = navState.sortColumn == column;
      final sortIcon = Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(
          isSorted
              ? (navState.sortAscending ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down)
              : CupertinoIcons.chevron_up_chevron_down,
          size: 14,
          color: isSorted
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      );

      final cellContent = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              label,
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          sortIcon,
        ],
      );

      final cell = InkWell(
        onTap: () => notifier.toggleSort(column),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: alignRight
              ? Align(alignment: Alignment.centerRight, child: cellContent)
              : cellContent,
        ),
      );

      if (flex != null) {
        return Expanded(flex: flex, child: cell);
      }
      return SizedBox(width: width, child: cell);
    }

    return Container(
      padding: const EdgeInsets.only(left: 8, right: 16, top: 8, bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8), // align with ListView padding
          buildHeaderCell(label: '名称', column: 'name', flex: 4),
          buildHeaderCell(label: '权限', column: 'permissions', width: 120),
          buildHeaderCell(label: '修改日期', column: 'date', width: 180),
          buildHeaderCell(label: '类型', column: 'type', width: 80),
          buildHeaderCell(label: '大小', column: 'size', width: 100, alignRight: true),
          const SizedBox(width: 80), // spacer for inline actions
        ],
      ),
    );
  }

  /// 上传拖入或选中的文件；APK 会执行安装而不是复制。
  Future<void> _pushFiles(
    BuildContext context,
    WidgetRef ref,
    List<XFile> files,
    String remotePath,
  ) async {
    final service = ref.read(fileManagerServiceProvider);
    for (final file in files) {
      if (file.path.toLowerCase().endsWith('.apk')) {
        final result = await ref
            .read(appManagementServiceProvider)
            .installApk(device.id, file.path);
        if (!context.mounted) {
          return;
        }
        _showSnack(
          context,
          '${file.name}: ${result.message}',
          isError: !result.isSuccess,
        );
        continue;
      }
      final result = await service.push(device.id, file.path, remotePath);
      if (!context.mounted) {
        return;
      }
      _showSnack(
        context,
        '${file.name}: ${result.message}',
        isError: !result.isSuccess,
      );
    }
    ref.invalidate(
      remoteFilesProvider(
        RemoteDirectoryRequest(deviceId: device.id, path: remotePath),
      ),
    );
  }
}

bool _isPreviewableTextFile(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  return const {
    'txt', 'log', 'json', 'xml', 'yaml', 'yml', 'ini', 'conf', 'properties',
    'sh', 'py', 'js', 'ts', 'html', 'css', 'md', 'csv', 'sql'
  }.contains(ext);
}

Future<void> _previewTextFile(
  BuildContext context,
  WidgetRef ref,
  String deviceId,
  String currentPath,
  RemoteFile file,
) async {
  bool loadingDismissed = false;
  void dismissLoading() {
    if (!loadingDismissed && context.mounted) {
      Navigator.of(context).pop();
      loadingDismissed = true;
    }
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('正在拉取文件以供预览...'),
        ],
      ),
    ),
  );

  try {
    final remoteFilePath = _joinRemotePath(currentPath, file.name);
    final tempDir = Directory.systemTemp.path;
    final localDir = Directory('$tempDir/AdbManage/previews');
    if (!localDir.existsSync()) {
      localDir.createSync(recursive: true);
    }
    final localPath = '${localDir.path}/${file.name}';
    
    final service = ref.read(fileManagerServiceProvider);
    final result = await service.pull(deviceId, remoteFilePath, localPath);

    dismissLoading();

    if (!result.isSuccess) {
      if (context.mounted) {
        _showSnack(context, '拉取文件失败: ${result.message}', isError: true);
      }
      return;
    }

    final ioFile = File(localPath);
    if (!ioFile.existsSync()) {
      if (context.mounted) {
        _showSnack(context, '拉取失败：未找到本地文件', isError: true);
      }
      return;
    }

    String content = '';
    bool isTruncated = false;
    final fileLength = ioFile.lengthSync();
    const int limit = 500 * 1024; // 500 KB

    if (fileLength > limit) {
      isTruncated = true;
      final bytes = await ioFile.openRead(0, limit).reduce((a, b) => [...a, ...b]);
      try {
        content = utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        content = String.fromCharCodes(bytes);
      }
    } else {
      try {
        content = await ioFile.readAsString(encoding: utf8);
      } catch (_) {
        final bytes = await ioFile.readAsBytes();
        content = utf8.decode(bytes, allowMalformed: true);
      }
    }

    if (context.mounted) {
      showDialog<void>(
        context: context,
        builder: (context) => _TextPreviewDialog(
          fileName: file.name,
          content: content,
          localPath: localPath,
          isTruncated: isTruncated,
          totalSize: file.size ?? fileLength,
        ),
      );
    }
  } catch (e) {
    dismissLoading();
    if (context.mounted) {
      _showSnack(context, '预览出错: $e', isError: true);
    }
  }
}

class _TextPreviewDialog extends ConsumerStatefulWidget {
  const _TextPreviewDialog({
    required this.fileName,
    required this.content,
    required this.localPath,
    required this.isTruncated,
    required this.totalSize,
  });

  final String fileName;
  final String content;
  final String localPath;
  final bool isTruncated;
  final int totalSize;

  @override
  ConsumerState<_TextPreviewDialog> createState() => _TextPreviewDialogState();
}

class _TextPreviewDialogState extends ConsumerState<_TextPreviewDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.content);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sizeText = _formatBytes(widget.totalSize);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 800,
        height: 600,
        color: theme.dialogTheme.backgroundColor ?? theme.colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Row(
                children: [
                  Icon(CupertinoIcons.doc, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.fileName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Actions
                  IconButton(
                    tooltip: '复制全部',
                    icon: const Icon(CupertinoIcons.doc_on_doc, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.content));
                      _showSnack(context, '已复制全部内容');
                    },
                  ),
                  IconButton(
                    tooltip: '使用系统默认程序打开',
                    icon: const Icon(CupertinoIcons.square_arrow_up, size: 20),
                    onPressed: () async {
                      try {
                        final opened = await ref.read(hostPlatformServiceProvider).openFile(widget.localPath);
                        if (!opened) {
                          throw Exception('System failed to open file');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          _showSnack(context, '无法打开文件: $e', isError: true);
                        }
                      }
                    },
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(CupertinoIcons.xmark, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Truncated Warning Banner
            if (widget.isTruncated)
              Container(
                color: Colors.amber.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.exclamationmark_triangle, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '此文件过大 (大小: $sizeText)，为防止卡死，当前仅展示前 500 KB 文本内容。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Content
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                color: theme.colorScheme.surfaceContainerLow,
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    child: TextField(
                      controller: _controller,
                      readOnly: true,
                      maxLines: null,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.45,
                        color: theme.colorScheme.onSurface,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Footer Info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '大小: $sizeText',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '编码: UTF-8',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PathTextField extends StatefulWidget {
  const _PathTextField({
    required this.initialPath,
    required this.onSubmitted,
  });

  final String initialPath;
  final ValueChanged<String> onSubmitted;

  @override
  State<_PathTextField> createState() => _PathTextFieldState();
}

class _PathTextFieldState extends State<_PathTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPath)
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: widget.initialPath.length),
      );
  }

  @override
  void didUpdateWidget(covariant _PathTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPath != widget.initialPath) {
      _controller.text = widget.initialPath;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: widget.initialPath.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      autofocus: true,
      controller: _controller,
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 8),
      ),
      style: Theme.of(context).textTheme.bodyMedium,
      onSubmitted: widget.onSubmitted,
    );
  }
}

/// 单个文件网格项，支持悬停高亮和显示浮动操作按钮。
