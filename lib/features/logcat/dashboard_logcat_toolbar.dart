part of '../dashboard_screen.dart';

class _LogcatToolbar extends StatelessWidget {
  const _LogcatToolbar({
    required this.state,
    required this.packageController,
    required this.tagController,
    required this.textController,
    required this.textFocusNode,
    required this.onStartStop,
    required this.onClear,
    required this.onImport,
    required this.onExport,
    required this.onViewModeChanged,
    required this.onLevelChanged,
    required this.onPackageChanged,
    required this.onPackageSubmitted,
    required this.onPackageHistoryRemoved,
    required this.onTagChanged,
    required this.onTagSubmitted,
    required this.onTagHistoryRemoved,
    required this.onTextChanged,
    required this.onTextSubmitted,
    required this.onTextHistoryRemoved,
    required this.onPause,
    required this.onAutoScroll,
    required this.onWrap,
  });

  final LogcatState state;
  final TextEditingController packageController;
  final TextEditingController tagController;
  final TextEditingController textController;
  final FocusNode textFocusNode;
  final VoidCallback onStartStop;
  final VoidCallback onClear;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final ValueChanged<LogcatViewMode> onViewModeChanged;
  final ValueChanged<LogcatLevelFilter> onLevelChanged;
  final ValueChanged<String> onPackageChanged;
  final ValueChanged<String> onPackageSubmitted;
  final ValueChanged<String> onPackageHistoryRemoved;
  final ValueChanged<String> onTagChanged;
  final ValueChanged<String> onTagSubmitted;
  final ValueChanged<String> onTagHistoryRemoved;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<String> onTextSubmitted;
  final ValueChanged<String> onTextHistoryRemoved;
  final VoidCallback onPause;
  final VoidCallback onAutoScroll;
  final VoidCallback onWrap;

  @override
  Widget build(BuildContext context) {
    final viewModeDropdown = _CompactDropdown<LogcatViewMode>(
      value: state.viewMode,
      items: {
        LogcatViewMode.standard: context.l10n.t('logcatStandardView'),
        LogcatViewMode.compact: context.l10n.t('logcatCompactView'),
        LogcatViewMode.plain: context.l10n.t('logcatPlainView'),
        LogcatViewMode.raw: context.l10n.t('logcatRawView'),
      },
      onChanged: onViewModeChanged,
    );
    final levelDropdown = _CompactDropdown<LogcatLevelFilter>(
      value: state.levelFilter,
      items: {for (final level in LogcatLevelFilter.values) level: level.label},
      onChanged: onLevelChanged,
    );
    final packageField = _HistoryTextField(
      controller: packageController,
      hintText: context.l10n.t('logcatPackageHint'),
      history: state.packageFilterHistory,
      onChanged: onPackageChanged,
      onSubmitted: onPackageSubmitted,
      onSelected: onPackageChanged,
      onHistoryRemoved: onPackageHistoryRemoved,
    );
    final tagField = _HistoryTextField(
      controller: tagController,
      hintText: context.l10n.t('logcatTagHint'),
      history: state.tagFilterHistory,
      onChanged: onTagChanged,
      onSubmitted: onTagSubmitted,
      onSelected: onTagChanged,
      onHistoryRemoved: onTagHistoryRemoved,
    );
    final textField = _HistoryTextField(
      controller: textController,
      focusNode: textFocusNode,
      hintText: context.l10n.t('filterLog'),
      history: state.textFilterHistory,
      prefixIcon: CupertinoIcons.search,
      onChanged: onTextChanged,
      onSubmitted: onTextSubmitted,
      onSelected: onTextChanged,
      onHistoryRemoved: onTextHistoryRemoved,
    );
    final buttons = [
      _LogcatIconButton(
        tooltip: state.isRunning
            ? context.l10n.t('stop')
            : context.l10n.t('start'),
        icon: state.isRunning ? CupertinoIcons.stop : CupertinoIcons.play,
        selected: state.isRunning,
        onPressed: onStartStop,
      ),
      _LogcatIconButton(
        tooltip: state.isPaused
            ? context.l10n.t('logcatResume')
            : context.l10n.t('logcatPause'),
        icon: state.isPaused ? CupertinoIcons.play : CupertinoIcons.pause,
        selected: state.isPaused,
        onPressed: onPause,
      ),
      _LogcatIconButton(
        tooltip: context.l10n.t('logcatAutoScroll'),
        icon: CupertinoIcons.arrow_down_to_line,
        selected: state.autoScroll,
        onPressed: onAutoScroll,
      ),
      _LogcatIconButton(
        tooltip: context.l10n.t('logcatWrapLines'),
        icon: CupertinoIcons.text_alignleft,
        selected: state.wrapLines,
        onPressed: onWrap,
      ),
      _LogcatIconButton(
        tooltip: context.l10n.t('logcatImport'),
        icon: CupertinoIcons.folder_open,
        onPressed: onImport,
      ),
      _LogcatIconButton(
        tooltip: context.l10n.t('logcatExport'),
        icon: CupertinoIcons.floppy_disk,
        onPressed: onExport,
      ),
      _LogcatIconButton(
        tooltip: context.l10n.t('clear'),
        icon: CupertinoIcons.clear,
        onPressed: onClear,
      ),
    ];

    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 1120) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: 132, child: viewModeDropdown),
                SizedBox(width: 140, child: levelDropdown),
                SizedBox(width: 220, child: packageField),
                SizedBox(width: 180, child: tagField),
                SizedBox(width: 260, child: textField),
                ...buttons,
              ],
            );
          }

          return Row(
            children: [
              SizedBox(width: 132, child: viewModeDropdown),
              const SizedBox(width: 8),
              SizedBox(width: 140, child: levelDropdown),
              const SizedBox(width: 8),
              Expanded(flex: 22, child: packageField),
              const SizedBox(width: 8),
              Expanded(flex: 18, child: tagField),
              const SizedBox(width: 8),
              Expanded(flex: 30, child: textField),
              const SizedBox(width: 10),
              for (final button in buttons) ...[
                button,
                if (button != buttons.last) const SizedBox(width: 6),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CompactDropdown<T> extends StatelessWidget {
  const _CompactDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isDense: true,
        isExpanded: true,
        borderRadius: BorderRadius.circular(12),
        icon: const Icon(CupertinoIcons.chevron_down, size: 16),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        items: items.entries
            .map(
              (entry) => DropdownMenuItem<T>(
                value: entry.key,
                child: Text(
                  entry.value,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(growable: false),
        onChanged: (value) {
          if (value != null) {
            onChanged(value);
          }
        },
      ),
    );
  }
}

class _HistoryTextField extends StatefulWidget {
  const _HistoryTextField({
    required this.controller,
    required this.hintText,
    required this.history,
    required this.onChanged,
    required this.onSubmitted,
    required this.onSelected,
    required this.onHistoryRemoved,
    this.prefixIcon,
    this.focusNode,
  });

  final TextEditingController controller;
  final String hintText;
  final List<String> history;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onHistoryRemoved;
  final IconData? prefixIcon;
  final FocusNode? focusNode;

  @override
  State<_HistoryTextField> createState() => _HistoryTextFieldState();
}

class _HistoryTextFieldState extends State<_HistoryTextField> {
  final GlobalKey _textFieldKey = GlobalKey();
  final LayerLink _layerLink = LayerLink();
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _hideOverlay();
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(_HistoryTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.history != oldWidget.history) {
      if (widget.history.isEmpty) {
        _hideOverlay();
      } else {
        _overlayEntry?.markNeedsBuild();
      }
    }
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      _openHistory();
    } else {
      widget.onSubmitted(widget.controller.text);
      _hideOverlay();
    }
  }

  void _selectHistory(String value) {
    widget.controller.text = value;
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    widget.onSelected(value);
    _hideOverlay();
    _focusNode.unfocus();
  }

  void _openHistory() {
    if (widget.history.isNotEmpty) {
      _showOverlay();
    }
  }

  void _toggleHistory() {
    if (_overlayEntry != null) {
      _hideOverlay();
      _focusNode.unfocus();
    } else {
      _focusNode.requestFocus();
      _openHistory();
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry?.markNeedsBuild();
      return;
    }
    if (!mounted || widget.history.isEmpty) return;

    final overlayState = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 42),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: _getTextFieldWidth(),
              child: TapRegion(
                groupId: 'logcat_history_filter_region_${identityHashCode(this)}',
                onTapOutside: (event) {
                  _hideOverlay();
                  _focusNode.unfocus();
                },
                child: _buildDropdownOverlayContent(),
              ),
            ),
          ),
        );
      },
    );

    overlayState.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  double _getTextFieldWidth() {
    final renderBox = _textFieldKey.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.size.width ?? 280.0;
  }

  Widget _buildDropdownOverlayContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      color: isDark ? const Color(0xff1e293b) : Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
            width: 1,
          ),
        ),
        constraints: const BoxConstraints(
          maxHeight: 250,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                context.l10n.t('searchHistory'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: widget.history.length,
                itemBuilder: (context, index) {
                  final item = widget.history[index];
                  return InkWell(
                    onTap: () {
                      _selectHistory(item);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.clock,
                            size: 14,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item,
                              style: Theme.of(context).textTheme.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(CupertinoIcons.clear, size: 14),
                            onPressed: () {
                              widget.onHistoryRemoved(item);
                              if (widget.controller.text == item) {
                                widget.controller.clear();
                                widget.onChanged('');
                              }
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            splashRadius: 16,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: _textFieldKey,
      height: 38,
      child: TapRegion(
        groupId: 'logcat_history_filter_region_${identityHashCode(this)}',
        child: CompositedTransformTarget(
          link: _layerLink,
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            minLines: 1,
            maxLines: 1,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: widget.prefixIcon == null
                  ? null
                  : Icon(widget.prefixIcon, size: 16),
              prefixIconConstraints: const BoxConstraints(minWidth: 32),
              suffixIcon: widget.history.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.l10n.t('logcatFilterHistory'),
                      icon: const Icon(CupertinoIcons.chevron_down, size: 16),
                      onPressed: _toggleHistory,
                    ),
              suffixIconConstraints: const BoxConstraints(minWidth: 30),
              hintText: widget.hintText,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            textInputAction: TextInputAction.done,
            onTap: _openHistory,
            onChanged: widget.onChanged,
            onSubmitted: (value) {
              widget.onSubmitted(value);
              _hideOverlay();
              _focusNode.unfocus();
            },
          ),
        ),
      ),
    );
  }
}

class _LogcatIconButton extends StatelessWidget {
  const _LogcatIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        isSelected: selected,
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
      ),
    );
  }
}
