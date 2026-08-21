part of '../dashboard_screen.dart';

final _cacheCleanupInProgressProvider =
    NotifierProvider.autoDispose<_CacheCleanupInProgressNotifier, bool>(
      _CacheCleanupInProgressNotifier.new,
    );

class _CacheCleanupInProgressNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setLoading(bool value) {
    state = value;
  }
}

extension _SettingsTabCacheActions on _SettingsTab {
  Widget _buildCacheSettingRow(
    BuildContext context,
    WidgetRef ref,
    Color brandGreen,
  ) {
    final isClearing = ref.watch(_cacheCleanupInProgressProvider);
    return _buildSettingRow(
      context,
      label: context.l10n.t('cacheFolders'),
      subtitle: context.l10n.t('cacheFoldersDesc'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: brandGreen,
              side: BorderSide(color: brandGreen),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: isClearing ? null : () => _openCacheFolder(context, ref),
            icon: const Icon(CupertinoIcons.folder_open, size: 18),
            label: Text(context.l10n.t('openCacheFolder')),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: brandGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor: brandGreen.withValues(alpha: 0.35),
              disabledForegroundColor: Colors.white70,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: isClearing
                ? null
                : () => _confirmAndClearCache(context, ref),
            icon: isClearing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(CupertinoIcons.trash, size: 18),
            label: Text(
              isClearing
                  ? context.l10n.t('clearingCache')
                  : context.l10n.t('clearCache'),
            ),
          ),
        ],
      ),
    );
  }

  /// 单个缓存目录直接打开；多个目录时先让用户按用途和路径选择。
  Future<void> _openCacheFolder(BuildContext context, WidgetRef ref) async {
    final folders = ref
        .read(cacheCleanupServiceProvider)
        .cacheFolders(existingOnly: true);
    if (folders.isEmpty) {
      _showSnack(context, context.l10n.t('noCacheFolders'));
      return;
    }

    CacheFolderLocation? selectedFolder;
    if (folders.length == 1) {
      selectedFolder = folders.single;
    } else {
      selectedFolder = await showDialog<CacheFolderLocation>(
        context: context,
        builder: (dialogContext) {
          return SimpleDialog(
            title: Text(context.l10n.t('selectCacheFolder')),
            children: folders
                .map(
                  (folder) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(dialogContext, folder),
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.folder_open, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_cacheFolderLabel(context, folder.kind)),
                              const SizedBox(height: 2),
                              Text(
                                folder.path,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
          );
        },
      );
    }
    if (selectedFolder == null || !context.mounted) {
      return;
    }

    final opened = await ref
        .read(hostPlatformServiceProvider)
        .openDirectory(selectedFolder.path);
    if (!opened && context.mounted) {
      _showSnack(
        context,
        context.l10n.t('openCacheFolderFailed'),
        isError: true,
      );
    }
  }

  String _cacheFolderLabel(BuildContext context, CacheFolderKind kind) {
    final key = switch (kind) {
      CacheFolderKind.app => 'appCacheFolder',
      CacheFolderKind.temporary => 'temporaryCacheFolder',
      CacheFolderKind.packages => 'packageCacheFolder',
      CacheFolderKind.helper => 'helperCacheFolder',
      CacheFolderKind.scrcpy => 'scrcpyCacheFolder',
    };
    return context.l10n.t(key);
  }

  Future<void> _confirmAndClearCache(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(context.l10n.t('clearCacheConfirmTitle')),
          content: Text(context.l10n.t('clearCacheConfirmMessage')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.l10n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.l10n.t('clearCache')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    final loading = ref.read(_cacheCleanupInProgressProvider.notifier);
    if (ref.read(_cacheCleanupInProgressProvider)) {
      return;
    }
    loading.setLoading(true);
    try {
      final result = await ref
          .read(cacheCleanupServiceProvider)
          .clearCacheFolders();
      if (!context.mounted) {
        return;
      }
      final message = context.l10n
          .t('clearCacheSuccess')
          .replaceAll('{size}', _formatCacheSize(result.freedBytes))
          .replaceAll('{count}', result.deletedFiles.toString());
      _showSnack(context, message);
    } catch (error) {
      if (context.mounted) {
        _showSnack(
          context,
          context.l10n.t('clearCacheFailed').replaceAll('{error}', '$error'),
          isError: true,
        );
      }
    } finally {
      loading.setLoading(false);
    }
  }

  String _formatCacheSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    if (unitIndex == 0) {
      return '${bytes}B';
    }
    return '${value.toStringAsFixed(1)} ${units[unitIndex]}';
  }
}
