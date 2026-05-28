part of 'terminal_tab.dart';

/// 终端专用紧凑按钮
class _TerminalButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final String tooltip;

  const _TerminalButton({
    required this.label,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

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

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.bookmark_outline, size: 20),
                const SizedBox(width: 8),
                Text(
                  context.l10n.t('commandFavorites'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.restore, size: 20),
                  tooltip: context.l10n.t('resetFavorites'),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(context.l10n.t('resetFavorites')),
                        content: const Text('确定重置并恢复默认收藏命令吗？'),
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
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: context.l10n.t('addFavorite'),
                  onPressed: () => _showAddFavoriteDialog(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: favorites.isEmpty
                  ? const Center(
                      child: Text(
                        '暂无收藏命令',
                        style: TextStyle(color: Colors.grey),
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
          ],
        ),
      ),
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
                    widget.command.title,
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
                      Icons.delete_outline,
                      size: 14,
                      color: Colors.redAccent,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 12,
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
                  icon: const Icon(Icons.edit_note, size: 12),
                  label: const Text('填入', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: widget.onFill,
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow, size: 12),
                  label: const Text('执行', style: TextStyle(fontSize: 11)),
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
}
