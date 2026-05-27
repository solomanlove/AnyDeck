import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/adb/adb_device.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/terminal/adb_terminal_session.dart';

class TerminalTab extends ConsumerStatefulWidget {
  final AdbDevice device;

  const TerminalTab({
    super.key,
    required this.device,
  });

  @override
  ConsumerState<TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends ConsumerState<TerminalTab> {
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // 延迟一帧，如果当前没有会话，自动创建一个默认终端
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final terminalState = ref.read(adbTerminalProvider);
      if (terminalState.getSessions(widget.device.id).isEmpty) {
        ref.read(adbTerminalProvider.notifier).createSession(widget.device.id);
      }
    });
  }

  @override
  void dispose() {
    _commandController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  void _handleSendCommand(String sessionId, String text) {
    if (text.trim().isEmpty) return;
    ref.read(adbTerminalProvider.notifier).sendCommand(widget.device.id, sessionId, text.trim());
    _commandController.clear();
    _inputFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final terminalState = ref.watch(adbTerminalProvider);
    final activeSession = terminalState.getActiveSession(widget.device.id);

    // 监听日志行数变化，自动滚动到底部
    ref.listen<AdbTerminalState>(
      adbTerminalProvider,
      (previous, next) {
        final prevActive = previous?.getActiveSession(widget.device.id);
        final nextActive = next.getActiveSession(widget.device.id);
        if (nextActive != null &&
            (prevActive == null || prevActive.lines.length != nextActive.lines.length)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 800;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧：终端主窗口
            Expanded(
              child: Column(
                children: [
                  // 终端多标签页栏
                  _buildTabsRow(context, terminalState),
                  const SizedBox(height: 8),

                  // 终端内容控制区
                  Expanded(
                    child: activeSession == null
                        ? _buildEmptyState(context)
                        : _buildTerminalConsole(context, activeSession),
                  ),
                ],
              ),
            ),

            // 右侧：常用命令栏（在非紧凑布局下直接侧边展示，紧凑布局下折叠/不展示）
            if (!isCompact) ...[
              const SizedBox(width: 16),
              SizedBox(
                width: 320,
                child: _FavoriteCommandsPanel(
                  device: widget.device,
                  activeSessionId: activeSession?.id,
                  onFillCommand: (cmd) {
                    _commandController.text = cmd;
                    _commandController.selection = TextSelection.fromPosition(
                      TextPosition(offset: cmd.length),
                    );
                    _inputFocusNode.requestFocus();
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 终端多标签页 TabRow
  Widget _buildTabsRow(BuildContext context, AdbTerminalState state) {
    final notifier = ref.read(adbTerminalProvider.notifier);
    final sessions = state.getSessions(widget.device.id);
    final activeSessionId = state.getActiveSessionId(widget.device.id);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // 标签页列表
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final isActive = session.id == activeSessionId;

                return Material(
                  color: isActive
                      ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => notifier.selectSession(widget.device.id, session.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                          ),
                          bottom: isActive
                              ? BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                )
                              : BorderSide.none,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.terminal_outlined,
                            size: 16,
                            color: isActive
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            session.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                              color: isActive
                                  ? Theme.of(context).colorScheme.onPrimaryContainer
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close, size: 12),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            splashRadius: 12,
                            onPressed: () => notifier.closeSession(widget.device.id, session.id),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 新建标签按钮
          Tooltip(
            message: context.l10n.t('newTerminal'),
            child: IconButton(
              icon: const Icon(Icons.add, size: 20),
              onPressed: () => notifier.createSession(widget.device.id),
            ),
          ),
        ],
      ),
    );
  }

  /// 终端为空状态
  Widget _buildEmptyState(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.terminal, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              '没有活动的终端调试窗口',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: Text(context.l10n.t('newTerminal')),
              onPressed: () =>
                  ref.read(adbTerminalProvider.notifier).createSession(widget.device.id),
            ),
          ],
        ),
      ),
    );
  }

  /// 交互式终端核心窗口
  Widget _buildTerminalConsole(BuildContext context, AdbTerminalSession session) {
    final notifier = ref.read(adbTerminalProvider.notifier);

    return Card(
      elevation: 4,
      color: const Color(0xFF1E1E2E), // 极具质感的深色调终端色
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // 终端日志输出区域
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SelectionArea(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: session.lines.length,
                    itemBuilder: (context, index) {
                      final line = session.lines[index];
                      return Text(
                        line.text,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          height: 1.3,
                          color: _getTerminalLineColor(line.type),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.grey, height: 1, thickness: 0.2),
            const SizedBox(height: 8),

            // 终端输入栏和控制快捷按钮
            Row(
              children: [
                // 提示符
                const Text(
                  'adb shell \$ ',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Color(0xFF89B4FA), // 柔和蓝
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),

                // 命令输入框，支持历史记录上下翻页
                Expanded(
                  child: KeyboardListener(
                    focusNode: FocusNode(), // 拦截键盘事件
                    onKeyEvent: (event) {
                      if (event is KeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          final prevCmd = notifier.getHistoryCommand(
                            widget.device.id,
                            session.id,
                            true,
                            _commandController.text,
                          );
                          if (prevCmd != null) {
                            _commandController.text = prevCmd;
                            _commandController.selection = TextSelection.fromPosition(
                              TextPosition(offset: prevCmd.length),
                            );
                          }
                        } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          final nextCmd = notifier.getHistoryCommand(
                            widget.device.id,
                            session.id,
                            false,
                            _commandController.text,
                          );
                          if (nextCmd != null) {
                            _commandController.text = nextCmd;
                            _commandController.selection = TextSelection.fromPosition(
                              TextPosition(offset: nextCmd.length),
                            );
                          }
                        }
                      }
                    },
                    child: TextField(
                      controller: _commandController,
                      focusNode: _inputFocusNode,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                      decoration: InputDecoration(
                        hintText: context.l10n.t('enterCommandHint'),
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      ),
                      onSubmitted: (text) => _handleSendCommand(session.id, text),
                    ),
                  ),
                ),

                // 控制按钮行
                Wrap(
                  spacing: 6,
                  children: [
                    // Ctrl+C
                    _TerminalButton(
                      label: context.l10n.t('ctrlC'),
                      onPressed: () => notifier.sendCtrlC(widget.device.id, session.id),
                      tooltip: '中断当前运行的命令',
                    ),
                    // 清屏
                    _TerminalButton(
                      label: context.l10n.t('clearLogs'),
                      onPressed: () => notifier.clearBuffer(widget.device.id, session.id),
                      tooltip: '清除控制台输出',
                    ),
                    // 重启终端
                    _TerminalButton(
                      label: context.l10n.t('reconnect'),
                      onPressed: () => notifier.restartSession(widget.device.id, session.id),
                      tooltip: '关闭并重启当前 ADB 终端进程',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 终端各行输出色彩映射
  Color _getTerminalLineColor(TerminalLineType type) {
    switch (type) {
      case TerminalLineType.stdout:
        return const Color(0xFFCDD6F4); // 柔白
      case TerminalLineType.stderr:
        return const Color(0xFFF38BA8); // 玫瑰红/粉
      case TerminalLineType.input:
        return const Color(0xFFA6E3A1); // 浅绿
      case TerminalLineType.info:
        return const Color(0xFFFAB387); // 亮黄/橙
    }
  }
}

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
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
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
                      await ref.read(favoriteCommandsProvider.notifier).resetFavorites();
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
                  ? const Center(child: Text('暂无收藏命令', style: TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      itemCount: favorites.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final cmd = favorites[index];
                        return _FavoriteItem(
                          command: cmd,
                          onRun: activeSessionId == null
                              ? null
                              : () {
                                  ref
                                      .read(adbTerminalProvider.notifier)
                                      .sendCommand(device.id, activeSessionId!, cmd.command);
                                },
                          onFill: () => onFillCommand(cmd.command),
                          onDelete: () {
                            ref.read(favoriteCommandsProvider.notifier).deleteFavorite(cmd.id);
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

  Future<void> _showAddFavoriteDialog(BuildContext context, WidgetRef ref) async {
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
          color: Theme.of(context).colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
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
                    icon: const Icon(Icons.delete_outline, size: 14, color: Colors.redAccent),
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
                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
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
