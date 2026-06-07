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
          final entries = ref
              .read(logcatControllerProvider.notifier)
              .visibleEntries();
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
    final alignedOffset =
        targetOffset - (viewportHeight / 2) + (estimatedHeight / 2);
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

    final activeEntryIndex =
        (activeMatchIndex >= 0 && activeMatchIndex < matchIndices.length)
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
                                    textForEntry: (entry) =>
                                        entry.message.isEmpty
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
