part of 'terminal_tab.dart';

/// 常用调试命令收藏侧边栏
class _FavoriteCommandsPanel extends ConsumerWidget {
  final AdbDevice device;
  final String? activeSessionId;
  final ValueChanged<String> onFillCommand;

  const _FavoriteCommandsPanel({
    required this.device,
    required this.activeSessionId,
    required this.onFillCommand,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteCommandsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 头部对齐栏（高度为 40，与左侧的标签栏对齐，样式一致）
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                CupertinoIcons.bookmark,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                context.l10n.t('commandFavorites'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Tooltip(
                message: context.l10n.t('resetFavorites'),
                child: IconButton(
                  icon: const Icon(
                    CupertinoIcons.arrow_counterclockwise,
                    size: 16,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 16,
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(context.l10n.t('resetFavorites')),
                        content: Text(context.l10n.t('resetFavoritesConfirm')),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(context.l10n.t('cancel')),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: Text(context.l10n.t('confirm')),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await ref
                          .read(favoriteCommandsProvider.notifier)
                          .resetFavorites();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: context.l10n.t('addFavorite'),
                child: IconButton(
                  icon: const Icon(CupertinoIcons.plus, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 16,
                  onPressed: () => _showAddFavoriteDialog(context, ref),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // 常用命令收藏列表卡片
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.02)
                  : Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.04),
                width: 1.0,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: favorites.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.t('noFavoriteCommands'),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      itemCount: favorites.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final cmd = favorites[index];
                        return _FavoriteItem(
                          command: cmd,
                          onRun: activeSessionId == null
                              ? null
                              : () {
                                  ref
                                      .read(adbTerminalProvider.notifier)
                                      .sendCommand(
                                        device.id,
                                        activeSessionId!,
                                        cmd.command,
                                      );
                                },
                          onFill: () => onFillCommand(cmd.command),
                          onDelete: () {
                            ref
                                .read(favoriteCommandsProvider.notifier)
                                .deleteFavorite(cmd.id);
                          },
                        );
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddFavoriteDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final titleController = TextEditingController();
    final commandController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.t('addFavorite')),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: context.l10n.t('commandTitle'),
                    hintText: context.l10n.t('enterTitleHint'),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: commandController,
                  decoration: InputDecoration(
                    labelText: context.l10n.t('commandText'),
                    hintText: context.l10n.t('enterCommandHintInput'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.t('confirm')),
            ),
          ],
        );
      },
    );

    if (confirmed == true &&
        titleController.text.isNotEmpty &&
        commandController.text.isNotEmpty) {
      await ref
          .read(favoriteCommandsProvider.notifier)
          .addFavorite(titleController.text, commandController.text);
    }
  }
}

/// 收藏项展示卡片
class _FavoriteItem extends ConsumerStatefulWidget {
  final FavoriteCommand command;
  final VoidCallback? onRun;
  final VoidCallback onFill;
  final VoidCallback onDelete;

  const _FavoriteItem({
    required this.command,
    required this.onRun,
    required this.onFill,
    required this.onDelete,
  });

  @override
  ConsumerState<_FavoriteItem> createState() => _FavoriteItemState();
}

class _FavoriteItemState extends ConsumerState<_FavoriteItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _commandTitle(context),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_hovering)
                  IconButton(
                    icon: const Icon(
                      CupertinoIcons.trash,
                      size: 14,
                      color: Colors.redAccent,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 12,
                    tooltip: context.l10n.t('deleteFavorite'),
                    onPressed: widget.onDelete,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.command.command,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Theme.of(
                  context,
                ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(CupertinoIcons.pencil, size: 12),
                  label: Text(
                    context.l10n.t('fillCommand'),
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: widget.onFill,
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(CupertinoIcons.play, size: 12),
                  label: Text(
                    context.l10n.t('runCommand'),
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: widget.onRun,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _commandTitle(BuildContext context) {
    final titleKey = widget.command.titleKey;
    return titleKey == null ? widget.command.title : context.l10n.t(titleKey);
  }
}
