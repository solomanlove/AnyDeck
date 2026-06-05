part of '../dashboard_screen.dart';

bool _isPreviewableTextFile(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  return const {
    'txt',
    'log',
    'json',
    'xml',
    'yaml',
    'yml',
    'ini',
    'conf',
    'properties',
    'sh',
    'py',
    'js',
    'ts',
    'html',
    'css',
    'md',
    'csv',
    'sql',
  }.contains(ext);
}

/// 拉取远端文本文件到临时目录，并在 Dialog 中做只读预览。
///
/// 大文件只读取前 500 KB，避免 TextField 渲染过大内容导致桌面端卡顿。
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
    const int limit = 500 * 1024;

    if (fileLength > limit) {
      isTruncated = true;
      final bytes = await ioFile
          .openRead(0, limit)
          .reduce((a, b) => [...a, ...b]);
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

class _TextPreviewDialog extends ConsumerWidget {
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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sizeText = _formatBytes(totalSize);

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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              child: Row(
                children: [
                  Icon(CupertinoIcons.doc, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '复制全部',
                    icon: const Icon(CupertinoIcons.doc_on_doc, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: content));
                      _showSnack(context, '已复制全部内容');
                    },
                  ),
                  IconButton(
                    tooltip: '使用系统默认程序打开',
                    icon: const Icon(CupertinoIcons.square_arrow_up, size: 20),
                    onPressed: () async {
                      try {
                        final opened = await ref
                            .read(hostPlatformServiceProvider)
                            .openFile(localPath);
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
            if (isTruncated)
              Container(
                color: Colors.amber.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.exclamationmark_triangle,
                      color: Colors.amber,
                      size: 20,
                    ),
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
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                color: theme.colorScheme.surfaceContainerLow,
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      content,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.45,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
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
