part of '../dashboard_screen.dart';

class _LogcatTab extends ConsumerStatefulWidget {
  const _LogcatTab({required this.device});

  final AdbDevice device;

  @override
  ConsumerState<_LogcatTab> createState() => _LogcatTabState();
}

class _LogcatTabState extends ConsumerState<_LogcatTab> {
  final ScrollController _verticalController = ScrollController();
  final TextEditingController _packageController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _logViewFocusNode = FocusNode(debugLabel: 'LogcatView');
  final FocusNode _textFilterFocusNode = FocusNode(
    debugLabel: 'LogcatTextFilter',
  );
  int _lastVisibleCount = 0;

  bool _searchBarVisible = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'LogcatSearchInput');
  int _activeMatchIndex = -1;
  String _lastSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchTextChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchTextChanged);
    _verticalController.dispose();
    _packageController.dispose();
    _tagController.dispose();
    _textController.dispose();
    _logViewFocusNode.dispose();
    _textFilterFocusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleSearchTextChanged() {
    final query = _searchController.text;
    if (query != _lastSearchQuery) {
      _lastSearchQuery = query;
      setState(() {
        _activeMatchIndex = 0;
      });
      if (query.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final entries = ref.read(logcatControllerProvider.notifier).visibleEntries();
          final queryLower = query.toLowerCase();
          final matches = <int>[];
          for (var i = 0; i < entries.length; i++) {
            if (entries[i].rawLine.toLowerCase().contains(queryLower)) {
              matches.add(i);
            }
          }
          if (matches.isNotEmpty) {
            _scrollToMatch(matches[0]);
          }
        });
      }
    }
  }

  void _closeSearch() {
    setState(() {
      _searchBarVisible = false;
      _searchController.clear();
      _activeMatchIndex = -1;
    });
    _logViewFocusNode.requestFocus();
  }

  void _openSearch() {
    setState(() {
      _searchBarVisible = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
    });
  }

  void _goToNextMatch(List<int> matchIndices) {
    if (matchIndices.isEmpty) {
      return;
    }
    setState(() {
      _activeMatchIndex = (_activeMatchIndex + 1) % matchIndices.length;
    });
    _scrollToMatch(matchIndices[_activeMatchIndex]);
  }

  void _goToPrevMatch(List<int> matchIndices) {
    if (matchIndices.isEmpty) {
      return;
    }
    setState(() {
      _activeMatchIndex =
          (_activeMatchIndex - 1 + matchIndices.length) % matchIndices.length;
    });
    _scrollToMatch(matchIndices[_activeMatchIndex]);
  }

  void _scrollToMatch(int entryIndex) {
    if (!_verticalController.hasClients || entryIndex < 0) {
      return;
    }

    if (ref.read(logcatControllerProvider).autoScroll) {
      ref.read(logcatControllerProvider.notifier).toggleAutoScroll();
    }

    final state = ref.read(logcatControllerProvider);
    double estimatedHeight = 28.0;
    if (state.viewMode == LogcatViewMode.compact) {
      estimatedHeight = state.wrapLines ? 34.0 : 32.0;
    } else if (state.viewMode == LogcatViewMode.standard) {
      estimatedHeight = state.wrapLines ? 34.0 : 28.0;
    } else {
      estimatedHeight = 16.0;
    }

    final targetOffset = entryIndex * estimatedHeight;
    final viewportHeight = _verticalController.position.viewportDimension;
    final alignedOffset = targetOffset - (viewportHeight / 2) + (estimatedHeight / 2);
    final clampedOffset = alignedOffset.clamp(
      0.0,
      _verticalController.position.maxScrollExtent,
    );

    _verticalController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
    );
  }



  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(logcatControllerProvider.notifier);
    final state = ref.watch(logcatControllerProvider);
    final entries = controller.visibleEntries();

    final query = _searchController.text;
    final List<int> matchIndices;
    if (query.isEmpty) {
      matchIndices = const [];
    } else {
      final queryLower = query.toLowerCase();
      matchIndices = [];
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final text = entry.rawLine.toLowerCase();
        if (text.contains(queryLower)) {
          matchIndices.add(i);
        }
      }
    }

    int activeMatchIndex = _activeMatchIndex;
    if (matchIndices.isEmpty) {
      activeMatchIndex = -1;
    } else if (activeMatchIndex >= matchIndices.length) {
      activeMatchIndex = matchIndices.length - 1;
    } else if (activeMatchIndex < 0 && matchIndices.isNotEmpty) {
      activeMatchIndex = 0;
    }

    final activeEntryIndex = (activeMatchIndex >= 0 && activeMatchIndex < matchIndices.length)
        ? matchIndices[activeMatchIndex]
        : -1;

    if (state.autoScroll &&
        entries.length != _lastVisibleCount &&
        _verticalController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_verticalController.hasClients) {
          return;
        }
        _verticalController.animateTo(
          _verticalController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      });
    }
    _lastVisibleCount = entries.length;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _LogcatToolbar(
            state: state,
            packageController: _packageController,
            tagController: _tagController,
            textController: _textController,
            textFocusNode: _textFilterFocusNode,
            onStartStop: () {
              state.isRunning
                  ? controller.stop()
                  : controller.start(widget.device.id);
            },
            onClear: controller.clear,
            onImport: () => _importLogcatFile(context, controller),
            onExport: () => _exportLogcatFile(context, controller),
            onViewModeChanged: controller.setViewMode,
            onLevelChanged: controller.setLevelFilter,
            onPackageChanged: controller.setPackageFilter,
            onPackageSubmitted: controller.commitPackageFilter,
            onPackageHistoryRemoved: controller.removePackageFilterHistory,
            onTagChanged: controller.setTagFilter,
            onTagSubmitted: controller.commitTagFilter,
            onTagHistoryRemoved: controller.removeTagFilterHistory,
            onTextChanged: controller.setTextFilter,
            onTextSubmitted: controller.commitTextFilter,
            onTextHistoryRemoved: controller.removeTextFilterHistory,
            onPause: controller.togglePaused,
            onAutoScroll: controller.toggleAutoScroll,
            onWrap: controller.toggleWrapLines,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                    _OpenLogcatSearchIntent(),
                SingleActivator(LogicalKeyboardKey.keyF, control: true):
                    _OpenLogcatSearchIntent(),
              },
              child: Actions(
                actions: {
                  _OpenLogcatSearchIntent:
                      CallbackAction<_OpenLogcatSearchIntent>(
                        onInvoke: (_) {
                          _openSearch();
                          return null;
                        },
                      ),
                },
                child: Focus(
                  focusNode: _logViewFocusNode,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _logViewFocusNode.requestFocus,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.5),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          children: [
                            state.error != null
                                ? _LogcatError(message: state.error!)
                                : state.viewMode == LogcatViewMode.raw
                                ? _LogcatTextList(
                                    entries: entries,
                                    controller: _verticalController,
                                    wrapLines: state.wrapLines,
                                    useLevelColor: true,
                                    textForEntry: (entry) => entry.rawLine,
                                    searchQuery: query,
                                    activeEntryIndex: activeEntryIndex,
                                  )
                                : state.viewMode == LogcatViewMode.plain
                                ? _LogcatTextList(
                                    entries: entries,
                                    controller: _verticalController,
                                    wrapLines: state.wrapLines,
                                    textForEntry: (entry) => entry.message.isEmpty
                                        ? entry.rawLine
                                        : entry.message,
                                    searchQuery: query,
                                    activeEntryIndex: activeEntryIndex,
                                  )
                                : state.viewMode == LogcatViewMode.compact
                                ? _CompactLogcatList(
                                    entries: entries,
                                    controller: _verticalController,
                                    wrapLines: state.wrapLines,
                                    searchQuery: query,
                                    activeEntryIndex: activeEntryIndex,
                                  )
                                : _StructuredLogcatTable(
                                    entries: entries,
                                    verticalController: _verticalController,
                                    wrapLines: state.wrapLines,
                                    searchQuery: query,
                                    activeEntryIndex: activeEntryIndex,
                                  ),
                            if (_searchBarVisible)
                              Positioned(
                                top: 8,
                                right: 16,
                                child: _LogcatSearchPanel(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  matchIndices: matchIndices,
                                  activeMatchIndex: activeMatchIndex,
                                  onClose: _closeSearch,
                                  onPrev: () => _goToPrevMatch(matchIndices),
                                  onNext: () => _goToNextMatch(matchIndices),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importLogcatFile(
    BuildContext context,
    LogcatController controller,
  ) async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Logcat', extensions: ['logcat', 'log', 'txt']),
      ],
    );
    if (file == null) {
      return;
    }

    try {
      final text = await File(file.path).readAsString();
      controller.importText(text);
      if (context.mounted) {
        _showSnack(context, context.l10n.t('logcatImportSuccess'));
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showSnack(
          context,
          context.l10n
              .t('logcatImportFailed')
              .replaceAll('{error}', error.toString()),
          isError: true,
        );
      }
    }
  }

  Future<void> _exportLogcatFile(
    BuildContext context,
    LogcatController controller,
  ) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Logcat', extensions: ['logcat', 'log', 'txt']),
      ],
      suggestedName: 'logcat_${DateTime.now().millisecondsSinceEpoch}.logcat',
    );
    if (location == null) {
      return;
    }

    try {
      await File(location.path).writeAsString(controller.exportVisibleText());
      if (context.mounted) {
        _showSnack(
          context,
          context.l10n
              .t('logcatExportSuccess')
              .replaceAll('{path}', location.path),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showSnack(
          context,
          context.l10n
              .t('logcatExportFailed')
              .replaceAll('{error}', error.toString()),
          isError: true,
        );
      }
    }
  }
}

class _OpenLogcatSearchIntent extends Intent {
  const _OpenLogcatSearchIntent();
}

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
      prefixIcon: Icons.search,
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
        icon: state.isRunning ? Icons.stop : Icons.play_arrow,
        selected: state.isRunning,
        onPressed: onStartStop,
      ),
      _LogcatIconButton(
        tooltip: state.isPaused
            ? context.l10n.t('logcatResume')
            : context.l10n.t('logcatPause'),
        icon: state.isPaused ? Icons.play_arrow : Icons.pause,
        selected: state.isPaused,
        onPressed: onPause,
      ),
      _LogcatIconButton(
        tooltip: context.l10n.t('logcatAutoScroll'),
        icon: Icons.vertical_align_bottom,
        selected: state.autoScroll,
        onPressed: onAutoScroll,
      ),
      _LogcatIconButton(
        tooltip: context.l10n.t('logcatWrapLines'),
        icon: Icons.wrap_text,
        selected: state.wrapLines,
        onPressed: onWrap,
      ),
      _LogcatIconButton(
        tooltip: context.l10n.t('logcatImport'),
        icon: Icons.file_open_outlined,
        onPressed: onImport,
      ),
      _LogcatIconButton(
        tooltip: context.l10n.t('logcatExport'),
        icon: Icons.save_alt,
        onPressed: onExport,
      ),
      _LogcatIconButton(
        tooltip: context.l10n.t('clear'),
        icon: Icons.cleaning_services,
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
    return DropdownButtonFormField<T>(
      initialValue: value,
      isDense: true,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(),
      ),
      items: items.entries
          .map(
            (entry) => DropdownMenuItem<T>(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
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
  final MenuController _menuController = MenuController();
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      widget.onSubmitted(widget.controller.text);
    }
  }

  void _selectHistory(String value) {
    widget.controller.text = value;
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    widget.onSelected(value);
    _menuController.close();
  }

  void _openHistory() {
    if (widget.history.isNotEmpty) {
      _menuController.open();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menuController,
      menuChildren: [
        for (final item in widget.history)
          SizedBox(
            width: 280,
            child: MenuItemButton(
              onPressed: () => _selectHistory(item),
              child: Row(
                children: [
                  Expanded(child: Text(item, overflow: TextOverflow.ellipsis)),
                  IconButton(
                    tooltip: context.l10n.t('logcatRemoveHistory'),
                    icon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      widget.onHistoryRemoved(item);
                      if (widget.controller.text == item) {
                        widget.controller.clear();
                        widget.onChanged('');
                      }
                      if (widget.history.length <= 1) {
                        _menuController.close();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
      builder: (context, controller, child) {
        return TextField(
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
                    icon: const Icon(Icons.arrow_drop_down, size: 18),
                    onPressed: _openHistory,
                  ),
            suffixIconConstraints: const BoxConstraints(minWidth: 30),
            hintText: widget.hintText,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 9,
            ),
            border: const OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
          onTap: _openHistory,
          onChanged: widget.onChanged,
          onSubmitted: (value) {
            widget.onSubmitted(value);
            _focusNode.unfocus();
          },
        );
      },
    );
  }
}

class _CompactLogcatList extends StatefulWidget {
  const _CompactLogcatList({
    required this.entries,
    required this.controller,
    required this.wrapLines,
    required this.searchQuery,
    required this.activeEntryIndex,
  });

  final List<LogcatEntry> entries;
  final ScrollController controller;
  final bool wrapLines;
  final String searchQuery;
  final int activeEntryIndex;

  @override
  State<_CompactLogcatList> createState() => _CompactLogcatListState();
}

class _CompactLogcatListState extends State<_CompactLogcatList> {
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final messageWidth = widget.wrapLines
            ? max(1.0, constraints.maxWidth - 176)
            : _estimatedLogTextWidth(
                widget.entries.map(
                  (entry) =>
                      entry.message.isEmpty ? entry.rawLine : entry.message,
                ),
                minWidth: max(560, constraints.maxWidth - 176),
                maxWidth: 5200,
                charWidth: 8,
              );
        final contentWidth = max(constraints.maxWidth, 176 + messageWidth);

        return SelectionArea(
          child: Scrollbar(
            controller: _horizontalController,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                height: constraints.maxHeight,
                child: Scrollbar(
                  controller: widget.controller,
                  child: ListView.builder(
                    controller: widget.controller,
                    padding: EdgeInsets.zero,
                    itemCount: widget.entries.length,
                    itemExtent: widget.wrapLines ? null : 32,
                    itemBuilder: (context, index) {
                      final entry = widget.entries[index];
                      final rowColor = index.isOdd
                          ? Theme.of(context).colorScheme.surfaceContainerLowest
                          : Theme.of(context).colorScheme.surface;
                      final textStyle = TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.25,
                        color: _levelForeground(entry.level),
                      );
                      return Container(
                        color: rowColor,
                        constraints: BoxConstraints(
                          minHeight: widget.wrapLines ? 34 : 32,
                        ),
                        child: Row(
                          crossAxisAlignment: widget.wrapLines
                              ? CrossAxisAlignment.start
                              : CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 118,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Text(
                                  _compactLogcatTime(entry.timestamp),
                                  style: textStyle.copyWith(
                                    color: Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 36,
                              child: _LevelBadge(level: entry.level),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: messageWidth,
                              child: _HighlightedText(
                                text: entry.message.isEmpty
                                    ? entry.rawLine
                                    : entry.message,
                                query: widget.searchQuery,
                                isActiveMatch: index == widget.activeEntryIndex,
                                style: textStyle,
                                softWrap: widget.wrapLines,
                                maxLines: widget.wrapLines ? null : 1,
                                overflow: widget.wrapLines
                                    ? TextOverflow.visible
                                    : TextOverflow.clip,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        style: IconButton.styleFrom(
          fixedSize: const Size(36, 36),
          minimumSize: const Size(36, 36),
          backgroundColor: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          foregroundColor: selected
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
        ),
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
      ),
    );
  }
}

class _StructuredLogcatTable extends StatefulWidget {
  const _StructuredLogcatTable({
    required this.entries,
    required this.verticalController,
    required this.wrapLines,
    required this.searchQuery,
    required this.activeEntryIndex,
  });

  final List<LogcatEntry> entries;
  final ScrollController verticalController;
  final bool wrapLines;
  final String searchQuery;
  final int activeEntryIndex;

  @override
  State<_StructuredLogcatTable> createState() => _StructuredLogcatTableState();
}

class _StructuredLogcatTableState extends State<_StructuredLogcatTable> {
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = _LogcatTableWidths.adaptive(
          constraints.maxWidth,
          widget.entries,
        );
        return SelectionArea(
          child: Scrollbar(
            controller: _horizontalController,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: max(widths.total, constraints.maxWidth),
                height: constraints.maxHeight,
                child: Column(
                  children: [
                    _LogcatTableHeader(widths: widths),
                    Expanded(
                      child: Scrollbar(
                        controller: widget.verticalController,
                        child: ListView.builder(
                          controller: widget.verticalController,
                          itemCount: widget.entries.length,
                          itemExtent: widget.wrapLines ? null : 28,
                          itemBuilder: (context, index) {
                            return _LogcatTableRow(
                              entry: widget.entries[index],
                              widths: widths,
                              index: index,
                              wrapLines: widget.wrapLines,
                              searchQuery: widget.searchQuery,
                              isActiveMatch: index == widget.activeEntryIndex,
                            );
                          },
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
    );
  }
}

class _LogcatTableWidths {
  const _LogcatTableWidths({
    required this.time,
    required this.pidTid,
    required this.tag,
    required this.packageName,
    required this.level,
    required this.message,
  });

  final double time;
  final double pidTid;
  final double tag;
  final double packageName;
  final double level;
  final double message;

  factory _LogcatTableWidths.adaptive(
    double viewportWidth,
    List<LogcatEntry> entries,
  ) {
    const base = 112.0 + 96.0 + 180.0 + 220.0 + 42.0 + 560.0;
    final extra = max(0.0, viewportWidth - base);
    final messageWidth = _estimatedLogTextWidth(
      entries.map(
        (entry) => entry.message.isEmpty ? entry.rawLine : entry.message,
      ),
      minWidth: 560 + extra * 0.60,
      maxWidth: 5200,
      charWidth: 8,
    );
    return _LogcatTableWidths(
      time: 112,
      pidTid: 96,
      tag: 180 + extra * 0.18,
      packageName: 220 + extra * 0.22,
      level: 50,
      message: messageWidth,
    );
  }

  double get total => time + pidTid + tag + packageName + level + message;
}

class _LogcatTableHeader extends StatelessWidget {
  const _LogcatTableHeader({required this.widths});

  final _LogcatTableWidths widths;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          _LogcatCell(
            width: widths.time,
            child: Text(context.l10n.t('logcatTime'), style: style),
          ),
          _LogcatCell(
            width: widths.pidTid,
            child: Text(context.l10n.t('logcatPidTid'), style: style),
          ),
          _LogcatCell(
            width: widths.tag,
            child: Text(context.l10n.t('logcatTag'), style: style),
          ),
          _LogcatCell(
            width: widths.packageName,
            child: Text(context.l10n.t('packageName'), style: style),
          ),
          _LogcatCell(
            width: widths.level,
            child: Text(context.l10n.t('logcatLevel'), style: style),
          ),
          _LogcatCell(
            width: widths.message,
            child: Text(context.l10n.t('logcatMessage'), style: style),
          ),
        ],
      ),
    );
  }
}

class _LogcatTableRow extends StatelessWidget {
  const _LogcatTableRow({
    required this.entry,
    required this.widths,
    required this.index,
    required this.wrapLines,
    required this.searchQuery,
    required this.isActiveMatch,
  });

  final LogcatEntry entry;
  final _LogcatTableWidths widths;
  final int index;
  final bool wrapLines;
  final String searchQuery;
  final bool isActiveMatch;

  @override
  Widget build(BuildContext context) {
    final rowColor = index.isOdd
        ? Theme.of(context).colorScheme.surfaceContainerLowest
        : Theme.of(context).colorScheme.surface;
    final textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12.5,
      height: 1.25,
      color: _levelForeground(entry.level),
    );

    return Container(
      constraints: BoxConstraints(minHeight: wrapLines ? 34 : 28),
      color: rowColor,
      child: Row(
        crossAxisAlignment: wrapLines
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          _LogcatCell(
            width: widths.time,
            child: _HighlightedText(
              text: entry.timestamp,
              query: searchQuery,
              isActiveMatch: isActiveMatch,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          _LogcatCell(
            width: widths.pidTid,
            child: _HighlightedText(
              text: entry.pidTid,
              query: searchQuery,
              isActiveMatch: isActiveMatch,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          _LogcatCell(
            width: widths.tag,
            child: _HighlightedText(
              text: entry.tag,
              query: searchQuery,
              isActiveMatch: isActiveMatch,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          _LogcatCell(
            width: widths.packageName,
            child: _HighlightedText(
              text: entry.packageName,
              query: searchQuery,
              isActiveMatch: isActiveMatch,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          _LogcatCell(
            width: widths.level,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            child: _LevelBadge(level: entry.level),
          ),
          _LogcatCell(
            width: widths.message,
            child: _HighlightedText(
              text: entry.message.isEmpty ? entry.rawLine : entry.message,
              query: searchQuery,
              isActiveMatch: isActiveMatch,
              style: textStyle,
              softWrap: wrapLines,
              maxLines: wrapLines ? null : 1,
              overflow: wrapLines ? TextOverflow.visible : TextOverflow.clip,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogcatCell extends StatelessWidget {
  const _LogcatCell({
    required this.width,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  });

  final double width;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(padding: padding, child: child),
    );
  }
}

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

class _LogcatTextList extends StatefulWidget {
  const _LogcatTextList({
    required this.entries,
    required this.controller,
    required this.wrapLines,
    required this.textForEntry,
    this.useLevelColor = false,
    required this.searchQuery,
    required this.activeEntryIndex,
  });

  final List<LogcatEntry> entries;
  final ScrollController controller;
  final bool wrapLines;
  final String Function(LogcatEntry entry) textForEntry;
  final bool useLevelColor;
  final String searchQuery;
  final int activeEntryIndex;

  @override
  State<_LogcatTextList> createState() => _LogcatTextListState();
}

class _LogcatTextListState extends State<_LogcatTextList> {
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = widget.wrapLines
            ? constraints.maxWidth
            : _estimatedLogTextWidth(
                widget.entries.map(widget.textForEntry),
                minWidth: constraints.maxWidth,
                maxWidth: 6000,
                charWidth: 8,
              );
        return SelectionArea(
          child: Scrollbar(
            controller: _horizontalController,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                height: constraints.maxHeight,
                child: Scrollbar(
                  controller: widget.controller,
                  child: ListView.builder(
                    controller: widget.controller,
                    padding: const EdgeInsets.all(8),
                    itemCount: widget.entries.length,
                    itemBuilder: (context, index) {
                      final entry = widget.entries[index];
                      final textColor = widget.useLevelColor
                          ? _levelForeground(entry.level)
                          : Theme.of(context).colorScheme.onSurface;
                      return _HighlightedText(
                        text: widget.textForEntry(entry),
                        query: widget.searchQuery,
                        isActiveMatch: index == widget.activeEntryIndex,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          height: 1.25,
                          color: textColor,
                        ),
                        softWrap: widget.wrapLines,
                        maxLines: widget.wrapLines ? null : 1,
                        overflow: widget.wrapLines
                            ? TextOverflow.visible
                            : TextOverflow.clip,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
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

double _estimatedLogTextWidth(
  Iterable<String> values, {
  required double minWidth,
  required double maxWidth,
  required double charWidth,
}) {
  var longest = 0;
  for (final value in values) {
    if (value.length > longest) {
      longest = value.length;
    }
  }
  final estimated = longest * charWidth + 24;
  return estimated.clamp(minWidth, maxWidth).toDouble();
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
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'SearchPanelKeyboard');

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
                color: widget.matchIndices.isEmpty && widget.controller.text.isNotEmpty
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            _SearchIconButton(
              icon: Icons.keyboard_arrow_up,
              tooltip: context.l10n.t('logcatSearchPrev'),
              onPressed: widget.matchIndices.isEmpty ? null : widget.onPrev,
            ),
            _SearchIconButton(
              icon: Icons.keyboard_arrow_down,
              tooltip: context.l10n.t('logcatSearchNext'),
              onPressed: widget.matchIndices.isEmpty ? null : widget.onNext,
            ),
            const SizedBox(width: 4),
            _SearchIconButton(
              icon: Icons.close,
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
        constraints: const BoxConstraints(
          minWidth: 26,
          minHeight: 26,
        ),
      ),
    );
  }
}
