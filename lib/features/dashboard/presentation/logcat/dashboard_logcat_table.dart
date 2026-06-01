part of '../dashboard_screen.dart';

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
