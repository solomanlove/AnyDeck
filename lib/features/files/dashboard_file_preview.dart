part of '../dashboard_screen.dart';

/// 拉取远程文件到隔离缓存，并使用宿主机默认应用打开。
Future<void> _previewRemoteFile(
  BuildContext context,
  WidgetRef ref,
  String deviceId,
  String currentPath,
  RemoteFile file,
) async {
  final result = await ref
      .read(filePreviewControllerProvider.notifier)
      .preview(
        deviceId: deviceId,
        remotePath: _joinRemotePath(currentPath, file.name),
        file: file,
      );
  if (!context.mounted || result.type == FilePreviewResultType.opened) return;
  if (result.type == FilePreviewResultType.canceled) return;

  final message = switch (result.type) {
    FilePreviewResultType.transferFailed =>
      context.l10n
          .t('filePreviewFailed')
          .replaceAll(
            '{error}',
            result.message == 'timeout'
                ? context.l10n.t('filePreviewTimeout')
                : result.message,
          ),
    FilePreviewResultType.openFailed => context.l10n.t('filePreviewOpenFailed'),
    _ => '',
  };
  if (message.isNotEmpty) {
    _showSnack(context, message, isError: true);
  }
}

/// 预览期间覆盖文件列表，提供明确的 Loading 和取消入口。
class _FilePreviewLoadingOverlay extends ConsumerWidget {
  const _FilePreviewLoadingOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewState = ref.watch(filePreviewControllerProvider);
    if (!previewState.isLoading) return const SizedBox.shrink();

    return Positioned.fill(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              ref.read(filePreviewControllerProvider.notifier).cancel(),
        },
        child: Focus(
          autofocus: true,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.28),
            child: Center(
              child: Card(
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          context.l10n.t('filePreviewLoading'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          previewState.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => ref
                              .read(filePreviewControllerProvider.notifier)
                              .cancel(),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: Text(context.l10n.t('cancel')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 为文件列表提供 Finder 风格的 Space 快捷预览。
class _FilePreviewShortcut extends ConsumerWidget {
  const _FilePreviewShortcut({
    required this.files,
    required this.selectedFile,
    required this.deviceId,
    required this.currentPath,
    required this.child,
  });

  final List<RemoteFile> files;
  final FileSelection? selectedFile;
  final String deviceId;
  final String currentPath;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    RemoteFile? selectedItem;
    for (final file in files) {
      if (selectedFile?.matches(
            deviceId,
            _joinRemotePath(currentPath, file.name),
          ) ??
          false) {
        selectedItem = file;
        break;
      }
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          final file = selectedItem;
          if (file != null && FilePreviewController.isPreviewable(file)) {
            unawaited(
              _previewRemoteFile(context, ref, deviceId, currentPath, file),
            );
          }
        },
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
