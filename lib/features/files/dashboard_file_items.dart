part of '../dashboard_screen.dart';

class _FileGridItem extends StatefulWidget {
  const _FileGridItem({
    required this.file,
    required this.deviceId,
    required this.currentPath,
    required this.onTap,
  });

  final RemoteFile file;
  final String deviceId;
  final String currentPath;
  final VoidCallback onTap;

  @override
  State<_FileGridItem> createState() => _FileGridItemState();
}

class _FileGridItemState extends State<_FileGridItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final theme = Theme.of(context);
    final remoteFilePath = _joinRemotePath(widget.currentPath, file.name);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: _hovering
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.08)
                : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovering
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : Colors.transparent,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Stack(
            children: [
              // 网格项内容
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _fileIcon(file),
                      size: 40,
                      color: file.isFolder
                          ? Colors.amber
                          : file.isLink
                          ? Colors.teal
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Tooltip(
                      message: file.linkTarget != null
                          ? '${file.name} -> ${file.linkTarget}'
                          : file.name,
                      child: Text(
                        file.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: file.isFolder ? FontWeight.w500 : null,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // 悬停时在右上角显示浮动操作按钮 (如果是文件且正在悬停)
              if (_hovering && !file.isFolder)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _RemoteFileActions(
                      deviceId: widget.deviceId,
                      remotePath: remoteFilePath,
                      fileName: file.name,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个文件行，支持悬停高亮和显示操作按钮。
class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.index,
    required this.file,
    required this.deviceId,
    required this.currentPath,
    required this.onTap,
  });

  final int index;
  final RemoteFile file;
  final String deviceId;
  final String currentPath;
  final VoidCallback onTap;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final theme = Theme.of(context);
    final cellStyle = theme.textTheme.bodyMedium?.copyWith(fontSize: 13);

    // 类型翻译
    String typeLabel = '文件';
    if (file.isFolder) {
      typeLabel = '文件夹';
    } else if (file.isLink) {
      typeLabel = '链接';
    }

    final remoteFilePath = _joinRemotePath(widget.currentPath, file.name);

    final Color? rowColor = widget.index % 2 == 0
        ? null
        : Theme.of(
            context,
          ).colorScheme.surfaceContainerLowest.withValues(alpha: 0.5);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: rowColor,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              // 名称
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    Icon(
                      _fileIcon(file),
                      size: 20,
                      color: file.isFolder
                          ? Colors.amber
                          : file.isLink
                          ? Colors.teal
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Tooltip(
                        message: file.linkTarget != null
                            ? '${file.name} -> ${file.linkTarget}'
                            : file.name,
                        child: Text(
                          file.name,
                          style: cellStyle?.copyWith(
                            fontWeight: file.isFolder ? FontWeight.w500 : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 权限
              SizedBox(
                width: 120,
                child: Text(
                  file.permissions,
                  style: cellStyle?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              // 修改日期
              SizedBox(
                width: 180,
                child: Text(file.modifiedDate, style: cellStyle),
              ),
              // 类型
              SizedBox(width: 80, child: Text(typeLabel, style: cellStyle)),
              // 大小
              SizedBox(
                width: 100,
                child: Text(
                  file.formattedSize,
                  style: cellStyle,
                  textAlign: TextAlign.right,
                ),
              ),
              // 操作 (悬停时显示)
              SizedBox(
                width: 80,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedOpacity(
                    opacity: _hovering ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 100),
                    child: IgnorePointer(
                      ignoring: !_hovering,
                      child: _RemoteFileActions(
                        deviceId: widget.deviceId,
                        remotePath: remoteFilePath,
                        fileName: file.name,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个远程文件的下载和删除操作。
class _RemoteFileActions extends ConsumerWidget {
  const _RemoteFileActions({
    required this.deviceId,
    required this.remotePath,
    required this.fileName,
  });

  final String deviceId;
  final String remotePath;
  final String fileName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(fileManagerServiceProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: context.l10n.t('pull'),
          icon: const Icon(CupertinoIcons.cloud_download, size: 18),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
          splashRadius: 16,
          onPressed: () async {
            final directory = await getDirectoryPath();
            if (directory == null || !context.mounted) {
              return;
            }
            final result = await service.pull(
              deviceId,
              remotePath,
              '$directory/$fileName',
            );
            if (context.mounted) {
              _showSnack(context, result.message, isError: !result.isSuccess);
            }
          },
        ),
        IconButton(
          tooltip: context.l10n.t('delete'),
          icon: const Icon(CupertinoIcons.trash, size: 18),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(6),
          splashRadius: 16,
          onPressed: () async {
            final confirmed = await _confirm(
              context,
              context.l10n.t('deleteFile').replaceAll('{file}', fileName),
            );
            if (!confirmed || !context.mounted) {
              return;
            }
            final result = await service.delete(deviceId, remotePath);
            if (context.mounted) {
              _showSnack(context, result.message, isError: !result.isSuccess);
            }
            if (result.isSuccess) {
              final currentPath = ref.read(fileNavigationProvider).currentPath;
              ref.invalidate(
                remoteFilesProvider(
                  RemoteDirectoryRequest(deviceId: deviceId, path: currentPath),
                ),
              );
            }
          },
        ),
      ],
    );
  }
}

int _compareFiles(
  RemoteFile left,
  RemoteFile right,
  String sortColumn,
  bool sortAscending,
) {
  // 文件夹始终排在前面
  if (left.isFolder != right.isFolder) {
    return left.isFolder ? -1 : 1;
  }

  int cmp;
  switch (sortColumn) {
    case 'size':
      final leftSize = left.size ?? 0;
      final rightSize = right.size ?? 0;
      cmp = leftSize.compareTo(rightSize);
      break;
    case 'date':
      cmp = left.modifiedDate.compareTo(right.modifiedDate);
      break;
    case 'type':
      cmp = left.type.index.compareTo(right.type.index);
      break;
    case 'permissions':
      cmp = left.permissions.compareTo(right.permissions);
      break;
    case 'name':
    default:
      cmp = left.name.toLowerCase().compareTo(right.name.toLowerCase());
      break;
  }

  return sortAscending ? cmp : -cmp;
}

/// 实时 logcat 查看器，支持启动/停止、清空和文本筛选。
