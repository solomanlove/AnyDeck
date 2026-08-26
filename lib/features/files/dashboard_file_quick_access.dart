part of '../dashboard_screen.dart';

/// Android 公共存储快捷入口，路径与系统标准外部存储目录保持一致。
class _FileQuickAccessItem {
  const _FileQuickAccessItem({
    required this.labelKey,
    required this.path,
    required this.icon,
    required this.colorRole,
  });

  final String labelKey;
  final String path;
  final IconData icon;
  final _FileQuickAccessColorRole colorRole;
}

enum _FileQuickAccessColorRole { primary, secondary, tertiary, error }

const _fileQuickAccessItems = <_FileQuickAccessItem>[
  _FileQuickAccessItem(
    labelKey: 'fileInternalStorage',
    path: '/storage/emulated/0',
    icon: Icons.storage_rounded,
    colorRole: _FileQuickAccessColorRole.primary,
  ),
  _FileQuickAccessItem(
    labelKey: 'fileCamera',
    path: '/storage/emulated/0/DCIM',
    icon: Icons.photo_camera_rounded,
    colorRole: _FileQuickAccessColorRole.tertiary,
  ),
  _FileQuickAccessItem(
    labelKey: 'fileDownloads',
    path: '/storage/emulated/0/Download',
    icon: Icons.download_rounded,
    colorRole: _FileQuickAccessColorRole.primary,
  ),
  _FileQuickAccessItem(
    labelKey: 'filePictures',
    path: '/storage/emulated/0/Pictures',
    icon: Icons.photo_rounded,
    colorRole: _FileQuickAccessColorRole.error,
  ),
  _FileQuickAccessItem(
    labelKey: 'fileMusic',
    path: '/storage/emulated/0/Music',
    icon: Icons.music_note_rounded,
    colorRole: _FileQuickAccessColorRole.error,
  ),
  _FileQuickAccessItem(
    labelKey: 'fileMovies',
    path: '/storage/emulated/0/Movies',
    icon: Icons.movie_rounded,
    colorRole: _FileQuickAccessColorRole.secondary,
  ),
  _FileQuickAccessItem(
    labelKey: 'fileDocuments',
    path: '/storage/emulated/0/Documents',
    icon: Icons.description_rounded,
    colorRole: _FileQuickAccessColorRole.tertiary,
  ),
];

const _harmonyQuickAccessItems = <_FileQuickAccessItem>[
  _FileQuickAccessItem(
    labelKey: 'fileTmpDirectory',
    path: '/data/local/tmp',
    icon: Icons.folder_special_rounded,
    colorRole: _FileQuickAccessColorRole.primary,
  ),
];

/// 根据 Files Tab 可用宽度组合快捷栏与原有文件内容。
class _FileQuickAccessLayout extends StatelessWidget {
  const _FileQuickAccessLayout({
    required this.deviceId,
    required this.currentPath,
    required this.onSelected,
    required this.child,
  });

  final String deviceId;
  final String currentPath;
  final ValueChanged<String> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1100;
        return Row(
          children: [
            _FileQuickAccessSidebar(
              deviceId: deviceId,
              currentPath: currentPath,
              compact: compact,
              onSelected: onSelected,
            ),
            VerticalDivider(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

/// Files Tab 左侧快捷栏；窄窗口只保留图标，避免压缩文件表格。
class _FileQuickAccessSidebar extends ConsumerWidget {
  const _FileQuickAccessSidebar({
    required this.deviceId,
    required this.currentPath,
    required this.compact,
    required this.onSelected,
  });

  final String deviceId;
  final String currentPath;
  final bool compact;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final favoritesAsync = ref.watch(fileFavoriteFoldersProvider);
    final favoritePaths = favoritesAsync.value?[deviceId] ?? const <String>[];
    final registeredDevices = ref.watch(deviceRegistryProvider);
    final isHarmony =
        registeredDevices.any((d) => d.id == deviceId && d.isHarmony);
    final quickAccessItems =
        isHarmony ? _harmonyQuickAccessItems : _fileQuickAccessItems;

    return ColoredBox(
      color: colorScheme.surfaceContainerLowest,
      child: SizedBox(
        width: compact ? 64 : 190,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 14,
            18,
            compact ? 8 : 14,
            12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!compact)
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 8),
                  child: Text(
                    context.l10n.t('fileQuickAccess'),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final item in quickAccessItems)
                      _buildItem(context, item, colorScheme),
                    const SizedBox(height: 12),
                    _buildFavoritesHeader(
                      context,
                      ref,
                      colorScheme,
                      enabled: favoritesAsync.hasValue,
                    ),
                    if (favoritesAsync.isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Center(
                          child: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    for (final path in favoritePaths)
                      _buildFavoriteItem(context, ref, path, colorScheme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoritesHeader(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme, {
    required bool enabled,
  }) {
    final addButton = IconButton(
      tooltip: context.l10n.t('fileAddCurrentFavorite'),
      icon: const Icon(Icons.add_rounded, size: 19),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      onPressed: enabled ? () => _addCurrentFolder(context, ref) : null,
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Center(child: addButton),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 2, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.t('fileFavoriteFolders'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          addButton,
        ],
      ),
    );
  }

  Widget _buildFavoriteItem(
    BuildContext context,
    WidgetRef ref,
    String path,
    ColorScheme colorScheme,
  ) {
    final label = _favoriteLabel(path);
    final selected = _normalizePath(currentPath) == _normalizePath(path);
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final content = Material(
      color: selected ? colorScheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => onSelected(path),
                borderRadius: BorderRadius.circular(10),
                child: Row(
                  mainAxisAlignment: compact
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    if (!compact) const SizedBox(width: 10),
                    Icon(
                      Icons.folder_special_rounded,
                      size: 22,
                      color: selected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.secondary,
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: foreground,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: context.l10n.t('fileRemoveFavorite'),
              icon: Icon(Icons.close_rounded, size: compact ? 15 : 17),
              color: foreground,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: compact ? 18 : 30,
                height: 36,
              ),
              onPressed: () => _removeFavorite(context, ref, path),
            ),
            if (!compact) const SizedBox(width: 2),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(message: path, child: content),
    );
  }

  Future<void> _addCurrentFolder(BuildContext context, WidgetRef ref) async {
    final normalizedCurrentPath = _normalizePath(currentPath);
    final registeredDevices = ref.read(deviceRegistryProvider);
    final isHarmony =
        registeredDevices.any((d) => d.id == deviceId && d.isHarmony);
    final quickAccessItems =
        isHarmony ? _harmonyQuickAccessItems : _fileQuickAccessItems;
    final isBuiltIn = quickAccessItems.any(
      (item) => _normalizePath(item.path) == normalizedCurrentPath,
    );
    if (isBuiltIn) {
      _showSnack(context, context.l10n.t('fileFavoriteAlreadyExists'));
      return;
    }

    final result = await ref
        .read(fileFavoriteFoldersProvider.notifier)
        .add(deviceId, normalizedCurrentPath);
    if (!context.mounted) return;
    final messageKey = switch (result) {
      FileFavoriteAddResult.added => 'fileFavoriteAdded',
      FileFavoriteAddResult.duplicate => 'fileFavoriteAlreadyExists',
      FileFavoriteAddResult.limitReached => 'fileFavoriteLimitReached',
    };
    _showSnack(context, context.l10n.t(messageKey));
  }

  Future<void> _removeFavorite(
    BuildContext context,
    WidgetRef ref,
    String path,
  ) async {
    await ref.read(fileFavoriteFoldersProvider.notifier).remove(deviceId, path);
    if (context.mounted) {
      _showSnack(context, context.l10n.t('fileFavoriteRemoved'));
    }
  }

  String _favoriteLabel(String path) {
    final normalized = _normalizePath(path);
    if (normalized == '/') return '/';
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  Widget _buildItem(
    BuildContext context,
    _FileQuickAccessItem item,
    ColorScheme colorScheme,
  ) {
    final label = context.l10n.t(item.labelKey);
    final selected = _normalizePath(currentPath) == _normalizePath(item.path);
    final iconColor = selected
        ? colorScheme.onPrimaryContainer
        : _resolveIconColor(colorScheme, item.colorRole);
    final itemContent = Material(
      color: selected ? colorScheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => onSelected(item.path),
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 42,
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              if (!compact) const SizedBox(width: 10),
              Icon(item.icon, size: 22, color: iconColor),
              if (!compact) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: selected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: compact
          ? Tooltip(message: label, child: itemContent)
          : itemContent,
    );
  }

  Color _resolveIconColor(
    ColorScheme colorScheme,
    _FileQuickAccessColorRole role,
  ) {
    return switch (role) {
      _FileQuickAccessColorRole.primary => colorScheme.primary,
      _FileQuickAccessColorRole.secondary => colorScheme.secondary,
      _FileQuickAccessColorRole.tertiary => colorScheme.tertiary,
      _FileQuickAccessColorRole.error => colorScheme.error,
    };
  }

  String _normalizePath(String path) {
    if (path == '/') return path;
    return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  }
}
