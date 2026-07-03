part of '../dashboard_screen.dart';

class _CompactLogcatList extends StatefulWidget {
  const _CompactLogcatList({
    required this.entries,
    required this.controller,
    required this.wrapLines,
    required this.searchQuery,
    required this.activeEntryIndex,
    required this.maxLogLength,
  });

  final List<LogcatEntry> entries;
  final ScrollController controller;
  final bool wrapLines;
  final String searchQuery;
  final int activeEntryIndex;
  final int maxLogLength;

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
        final double messageWidth = widget.wrapLines
            ? max(1.0, constraints.maxWidth - 176.0)
            : (widget.maxLogLength * 8.0 + 24.0).clamp(
                max(560.0, constraints.maxWidth - 176.0),
                5200.0,
              ).toDouble();
        final double contentWidth = max(constraints.maxWidth, 176.0 + messageWidth);

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

class _LogcatTextList extends StatefulWidget {
  const _LogcatTextList({
    required this.entries,
    required this.controller,
    required this.wrapLines,
    required this.textForEntry,
    this.useLevelColor = false,
    required this.searchQuery,
    required this.activeEntryIndex,
    required this.maxLogLength,
  });

  final List<LogcatEntry> entries;
  final ScrollController controller;
  final bool wrapLines;
  final String Function(LogcatEntry entry) textForEntry;
  final bool useLevelColor;
  final String searchQuery;
  final int activeEntryIndex;
  final int maxLogLength;

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
        final double contentWidth = widget.wrapLines
            ? constraints.maxWidth
            : (widget.maxLogLength * 8.0 + 24.0).clamp(
                constraints.maxWidth,
                6000.0,
              ).toDouble();
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
