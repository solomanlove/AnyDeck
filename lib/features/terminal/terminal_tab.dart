import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/adb/discovered_device.dart';
import '../../core/providers/app_providers.dart';
import '../../core/terminal/adb_terminal_session.dart';
import '../../core/terminal/favorite_commands.dart';

part 'terminal_favorites.dart';
part 'terminal_session_lifecycle.dart';

class TerminalTab extends ConsumerStatefulWidget {
  final DiscoveredDevice device;
  final bool isVisible;

  const TerminalTab({super.key, required this.device, required this.isVisible});

  @override
  ConsumerState<TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends ConsumerState<TerminalTab> {
  late final AdbTerminalNotifier _sessionNotifier;
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _inputFocusNode;

  @override
  void initState() {
    super.initState();
    _sessionNotifier = ref.read(adbTerminalProvider.notifier);
    _inputFocusNode = FocusNode(
      debugLabel: 'TerminalInput',
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final terminalState = ref.read(adbTerminalProvider);
          final activeSession = terminalState.getActiveSession(
            widget.device.id,
          );
          if (activeSession == null) return KeyEventResult.ignored;

          final notifier = ref.read(adbTerminalProvider.notifier);
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            final prevCmd = notifier.getHistoryCommand(
              widget.device.id,
              activeSession.id,
              true,
              _commandController.text,
            );
            if (prevCmd != null) {
              _commandController.text = prevCmd;
              _commandController.selection = TextSelection.fromPosition(
                TextPosition(offset: prevCmd.length),
              );
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            final nextCmd = notifier.getHistoryCommand(
              widget.device.id,
              activeSession.id,
              false,
              _commandController.text,
            );
            if (nextCmd != null) {
              _commandController.text = nextCmd;
              _commandController.selection = TextSelection.fromPosition(
                TextPosition(offset: nextCmd.length),
              );
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );
    // 延迟一帧，如果当前没有会话，自动创建一个默认终端
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncTerminalSession(this);
    });
  }

  @override
  void didUpdateWidget(covariant TerminalTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id ||
        oldWidget.isVisible != widget.isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (oldWidget.device.id != widget.device.id) {
          _sessionNotifier.suspendDevice(oldWidget.device.id);
        }
        _syncTerminalSession(this);
      });
    }
  }

  @override
  void dispose() {
    final deviceId = widget.device.id;
    scheduleMicrotask(() => _sessionNotifier.suspendDevice(deviceId));
    _commandController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(deviceOnlineProvider(widget.device.id));
    if (!isOnline) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.bolt_slash, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('手机离线，无法使用终端调试功能'),
          ],
        ),
      );
    }

    final terminalState = ref.watch(adbTerminalProvider);
    final activeSession = terminalState.getActiveSession(widget.device.id);

    // 提示符可能追加在原行，行数不变时也需要滚动到最新回显。
    ref.listen<AdbTerminalState>(adbTerminalProvider, (previous, next) {
      final prevActive = previous?.getActiveSession(widget.device.id);
      final nextActive = next.getActiveSession(widget.device.id);
      if (nextActive != null &&
          (prevActive == null ||
              prevActive.lines != nextActive.lines)) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollTerminalToBottom(_scrollController),
        );
      }
    });

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

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                  child: Material(
                    color: isActive
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () =>
                          notifier.selectSession(widget.device.id, session.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isActive
                                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.chevron_left_slash_chevron_right,
                              size: 14,
                              color: isActive
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              context.l10n
                                  .t('terminalTabLabel')
                                  .replaceAll('{index}', '${index + 1}'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isActive
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => notifier.closeSession(
                                widget.device.id,
                                session.id,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  CupertinoIcons.xmark,
                                  size: 10,
                                  color: isActive
                                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)
                                      : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          ],
                        ),
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
              icon: const Icon(CupertinoIcons.plus, size: 20),
              onPressed: () => ref
                  .read(adbTerminalProvider.notifier)
                  .createSession(
                    widget.device.id,
                    isHarmony: widget.device.isHarmony,
                  ),
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
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.chevron_left_slash_chevron_right,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.t('noActiveTerminal'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(CupertinoIcons.plus),
              label: Text(context.l10n.t('newTerminal')),
              onPressed: () => ref
                  .read(adbTerminalProvider.notifier)
                  .createSession(
                    widget.device.id,
                    isHarmony: widget.device.isHarmony,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 判断终端回显行是否为 shell 就绪提示符（如 "pudding:/ $ " 或 "perseus:/ # "）
  bool _isPromptLine(TerminalLine line) {
    if (line.type != TerminalLineType.stdout) return false;
    final trimmed = line.text.trimRight();
    return trimmed.isNotEmpty &&
        (trimmed.endsWith(r'$') ||
            trimmed.endsWith('#') ||
            trimmed.endsWith('>') ||
            trimmed.endsWith('%'));
  }

  /// 交互式终端核心窗口
  Widget _buildTerminalConsole(
    BuildContext context,
    AdbTerminalSession session,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final consoleBg = isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF5F5F7);
    final inputColor = isDark ? const Color(0xFFA6E3A1) : const Color(0xFF111827);

    // 检查末行是否为 shell 回显的就绪提示符（如 "pudding:/ $ "）
    final hasPrompt = !session.isHarmony && session.lines.isNotEmpty && _isPromptLine(session.lines.last);
    final rawPrompt = hasPrompt ? session.lines.last.text : '';
    final promptText = session.isHarmony ? r'$ ' : rawPrompt.isEmpty
        ? ''
        : (rawPrompt.endsWith(' ') ? rawPrompt : '$rawPrompt ');
    // 设备提示符或换行占位空行由输入行承接，避免回车后多出空白行。
    final lastLine = session.lines.lastOrNull;
    final hideLast = hasPrompt || (lastLine?.text == '' && lastLine?.l10nKey == null);
    final historyLinesCount = session.lines.length - (hideLast ? 1 : 0);

    return Card(
      elevation: 4,
      color: consoleBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) => _inputFocusNode.requestFocus(),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: SelectionArea(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: historyLinesCount + 1,
              itemBuilder: (context, index) {
                if (index == historyLinesCount) {
                  // 命令行输入行：将设备回显的提示符与输入框保持在同一行（如 "pudding:/ $ " 后紧跟光标）
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (promptText.isNotEmpty)
                        Text(
                          promptText,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.3,
                            color: _getTerminalLineColor(
                              TerminalLineType.stdout,
                              isDark,
                            ),
                          ),
                        ),
                      Expanded(
                        child: TextField(
                          controller: _commandController,
                          focusNode: _inputFocusNode,
                          cursorWidth: 8.0,
                          cursorRadius: Radius.zero,
                          cursorColor: isDark
                              ? const Color(0xFFCDD6F4)
                              : const Color(0xFF111827),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.3,
                            color: inputColor,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 2),
                          ),
                          onSubmitted: (text) =>
                              _sendTerminalCommand(this, session.id, text),
                        ),
                      ),
                    ],
                  );
                }

                final line = session.lines[index];

                // 普通的 stdout/stderr/info 日志渲染
                return Text(
                  _terminalLineText(context, line),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.3,
                    color: _getTerminalLineColor(line.type, isDark),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _terminalLineText(BuildContext context, TerminalLine line) {
    final key = line.l10nKey;
    if (key == null) return line.text;

    var text = context.l10n.t(key);
    for (final entry in line.l10nArgs.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value);
    }
    return text;
  }

  /// 终端各行输出色彩映射
  Color _getTerminalLineColor(TerminalLineType type, bool isDark) {
    switch (type) {
      case TerminalLineType.stdout:
        return isDark
            ? const Color(0xFFCDD6F4)
            : const Color(0xFF374151); // 柔白 vs 深灰
      case TerminalLineType.stderr:
        return isDark
            ? const Color(0xFFF38BA8)
            : const Color(0xFFDC2626); // 粉红 vs 鲜红
      case TerminalLineType.input:
        return isDark
            ? const Color(0xFFA6E3A1)
            : const Color(0xFF111827); // 浅绿 vs 纯黑
      case TerminalLineType.info:
        return isDark
            ? const Color(0xFFFAB387)
            : const Color(0xFFD97706); // 橙黄 vs 褐黄
    }
  }
}
