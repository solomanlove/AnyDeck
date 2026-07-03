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
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandGreen,
          foregroundColor: Colors.white,
          disabledBackgroundColor: brandGreen.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    );
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
