part of '../dashboard_screen.dart';

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final LogcatLevel level;

  @override
  Widget build(BuildContext context) {
    final label = level == LogcatLevel.unknown ? '?' : level.label;
    final background = _levelBackground(level);
    final foreground = level == LogcatLevel.warning
        ? const Color(0xff1f2937)
        : Colors.white;

    return Container(
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _LogcatError extends StatelessWidget {
  const _LogcatError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

/// 用于承载一组相关操作按钮的小型复用卡片。
class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: children),
          ],
        ),
      ),
    );
  }
}

/// 操作面板中统一样式的 outlined 图标按钮。
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}

/// 带开关状态的操作按钮，点击在开/关之间切换，图标和颜色随状态变化。
class _ToggleActionButton extends StatefulWidget {
  const _ToggleActionButton({
    required this.iconOn,
    required this.iconOff,
    required this.label,
    required this.onToggle,
    this.value,
  });

  final IconData iconOn;
  final IconData iconOff;
  final String label;
  final ValueChanged<bool> onToggle;
  final bool? value;

  @override
  State<_ToggleActionButton> createState() => _ToggleActionButtonState();
}

class _ToggleActionButtonState extends State<_ToggleActionButton> {
  bool _localIsOn = false;

  bool get _effectiveIsOn => widget.value ?? _localIsOn;

  @override
  void initState() {
    super.initState();
    if (widget.value != null) {
      _localIsOn = widget.value!;
    }
  }

  @override
  void didUpdateWidget(covariant _ToggleActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null && widget.value != oldWidget.value) {
      _localIsOn = widget.value!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOn = _effectiveIsOn;
    return isOn
        ? FilledButton.icon(
            icon: Icon(widget.iconOn, size: 18),
            label: Text(widget.label),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            onPressed: () {
              setState(() => _localIsOn = false);
              widget.onToggle(false);
            },
          )
        : OutlinedButton.icon(
            icon: Icon(widget.iconOff, size: 18),
            label: Text(widget.label),
            onPressed: () {
              setState(() => _localIsOn = true);
              widget.onToggle(true);
            },
          );
  }
}

Color _levelBackground(LogcatLevel level) {
  return switch (level) {
    LogcatLevel.verbose => const Color(0xff6b7280),
    LogcatLevel.debug => const Color(0xff65a30d),
    LogcatLevel.info => const Color(0xff2563eb),
    LogcatLevel.warning => const Color(0xfff59e0b),
    LogcatLevel.error => const Color(0xffef4444),
    LogcatLevel.assertLevel => const Color(0xffb91c1c),
    LogcatLevel.unknown => const Color(0xff64748b),
  };
}

String _compactLogcatTime(String timestamp) {
  final parts = timestamp.split(RegExp(r'\s+'));
  return parts.isEmpty ? timestamp : parts.last;
}

Color _levelForeground(LogcatLevel level) {
  return switch (level) {
    LogcatLevel.verbose => const Color(0xff4b5563),
    LogcatLevel.debug => const Color(0xff2f7d32),
    LogcatLevel.info => const Color(0xff1d4ed8),
    LogcatLevel.warning => const Color(0xffd97706),
    LogcatLevel.error => const Color(0xffef4444),
    LogcatLevel.assertLevel => const Color(0xffb91c1c),
    LogcatLevel.unknown => const Color(0xff334155),
  };
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    required this.style,
    required this.isActiveMatch,
    this.overflow,
    this.maxLines,
    this.softWrap,
  });

  final String text;
  final String query;
  final TextStyle style;
  final bool isActiveMatch;
  final TextOverflow? overflow;
  final int? maxLines;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(
        text,
        style: style,
        overflow: overflow,
        maxLines: maxLines,
        softWrap: softWrap,
      );
    }

    final queryLower = query.toLowerCase();
    final textLower = text.toLowerCase();

    final spans = <TextSpan>[];
    var start = 0;

    final activeBg = Colors.orange.withValues(alpha: 0.4);
    final inactiveBg = Colors.yellow.withValues(alpha: 0.4);

    while (true) {
      final index = textLower.indexOf(queryLower, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }

      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }

      final matchText = text.substring(index, index + query.length);
      spans.add(
        TextSpan(
          text: matchText,
          style: TextStyle(
            backgroundColor: isActiveMatch ? activeBg : inactiveBg,
            fontWeight: isActiveMatch ? FontWeight.bold : null,
          ),
        ),
      );

      start = index + query.length;
    }

    return Text.rich(
      TextSpan(children: spans),
      style: style,
      overflow: overflow,
      maxLines: maxLines,
      softWrap: softWrap,
    );
  }
}

class _LogcatSearchPanel extends StatefulWidget {
  const _LogcatSearchPanel({
    required this.controller,
    required this.focusNode,
    required this.matchIndices,
    required this.activeMatchIndex,
    required this.onClose,
    required this.onPrev,
    required this.onNext,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<int> matchIndices;
  final int activeMatchIndex;
  final VoidCallback onClose;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  State<_LogcatSearchPanel> createState() => _LogcatSearchPanelState();
}

class _LogcatSearchPanelState extends State<_LogcatSearchPanel> {
  final FocusNode _keyboardFocusNode = FocusNode(
    debugLabel: 'SearchPanelKeyboard',
  );

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final countText = widget.matchIndices.isEmpty
        ? context.l10n.t('logcatNoMatches')
        : '${widget.activeMatchIndex + 1} / ${widget.matchIndices.length}';

    return Container(
      width: 340,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: KeyboardListener(
        focusNode: _keyboardFocusNode,
        onKeyEvent: (KeyEvent event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
              if (isShiftPressed) {
                widget.onPrev();
              } else {
                widget.onNext();
              }
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              widget.onClose();
            }
          }
        },
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: context.l10n.t('logcatSearchPlaceholder'),
                  hintStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              countText,
              style: TextStyle(
                fontSize: 12,
                color:
                    widget.matchIndices.isEmpty &&
                        widget.controller.text.isNotEmpty
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            _SearchIconButton(
              icon: CupertinoIcons.chevron_up,
              tooltip: context.l10n.t('logcatSearchPrev'),
              onPressed: widget.matchIndices.isEmpty ? null : widget.onPrev,
            ),
            _SearchIconButton(
              icon: CupertinoIcons.chevron_down,
              tooltip: context.l10n.t('logcatSearchNext'),
              onPressed: widget.matchIndices.isEmpty ? null : widget.onNext,
            ),
            const SizedBox(width: 4),
            _SearchIconButton(
              icon: CupertinoIcons.xmark,
              tooltip: context.l10n.t('logcatSearchClose'),
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchIconButton extends StatelessWidget {
  const _SearchIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      ),
    );
  }
}
