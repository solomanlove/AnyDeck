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

/// 异步统计缓存目录总占用大小的 Provider。
final _cacheSizeProvider = FutureProvider.autoDispose<int>((ref) async {
  final service = ref.watch(cacheCleanupServiceProvider);
  var total = 0;
  for (final folder in service.cacheFolders(existingOnly: true)) {
    final dir = Directory(folder.path);
    if (dir.existsSync()) {
      try {
        await for (final child in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (child is File) {
            total += await child.length();
          }
        }
      } catch (_) {}
    }
  }
  return total;
});

extension _SettingsTabCacheActions on _SettingsTab {
  Widget _buildCacheSettingRow(
    BuildContext context,
    WidgetRef ref,
    Color brandGreen,
  ) {
    final isClearing = ref.watch(_cacheCleanupInProgressProvider);
    final cacheSizeAsync = ref.watch(_cacheSizeProvider);
    final sizeText = cacheSizeAsync.maybeWhen(
      data: (bytes) => _formatCacheSize(bytes),
      orElse: () => '',
    );
    final desc = context.l10n.t('cacheFoldersDesc');
    final subtitle = sizeText.isNotEmpty
        ? (context.l10n.locale.languageCode == 'zh'
            ? '$desc，已占用 $sizeText'
            : '$desc ($sizeText used)')
        : desc;

    return _buildSettingRow(
      context,
      label: context.l10n.t('cacheFolders'),
      subtitle: subtitle,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTextActionButton(
            text: context.l10n.t('openCacheFolder'),
            color: const Color(0xFF2563EB),
            onTap: isClearing ? null : () => _openCacheFolder(context, ref),
          ),
          const SizedBox(width: 16),
          if (isClearing)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFDC2626),
              ),
            )
          else
            _buildTextActionButton(
              text: context.l10n.t('clearCache'),
              color: const Color(0xFFDC2626),
              onTap: () => _confirmAndClearCache(context, ref),
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
      // 清理完成后重新刷新缓存大小
      ref.invalidate(_cacheSizeProvider);
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
    if (bytes <= 0) {
      return '0 B';
    }
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    final formatted = value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    return '$formatted ${units[unitIndex]}';
  }
}
