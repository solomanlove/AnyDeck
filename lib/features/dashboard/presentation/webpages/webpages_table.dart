part of 'webpages_tab.dart';

class _WebpageTableWidths {
  final double title;
  final double url;
  final double type;

  const _WebpageTableWidths({
    required this.title,
    required this.url,
    required this.type,
  });

  factory _WebpageTableWidths.adaptive({required double viewportWidth}) {
    const double minTotal = 700.0;
    if (viewportWidth > minTotal) {
      final double extra = viewportWidth - minTotal;
      return _WebpageTableWidths(
        title: 250.0 + extra * 0.4,
        url: 350.0 + extra * 0.6,
        type: 100.0,
      );
    } else {
      return const _WebpageTableWidths(title: 250.0, url: 350.0, type: 100.0);
    }
  }

  double get total => title + url + type;
}

class _WebpageTable extends StatefulWidget {
  final List<WebpageTarget> targets;
  final String? selectedId;
  final _WebpageTableWidths widths;
  final ValueChanged<WebpageTarget> onSelected;

  const _WebpageTable({
    required this.targets,
    required this.selectedId,
    required this.widths,
    required this.onSelected,
  });

  @override
  State<_WebpageTable> createState() => _WebpageTableState();
}

class _WebpageTableState extends State<_WebpageTable> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  /// 显示右键上下文菜单，支持复制 URL 地址
  void _showContextMenu(
    BuildContext context,
    Offset position,
    WebpageTarget target,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final popupBgColor =
        isDark ? const Color(0xff1e222b) : const Color(0xfff5f6f8);
    final popupBorderColor =
        isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xffeceef1);

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: popupBgColor,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: popupBorderColor, width: 1),
      ),
      items: [
        PopupMenuItem<String>(
          value: 'copy_url',
          height: 38,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.doc_on_doc, size: 14),
              const SizedBox(width: 8),
              Text(
                context.l10n.t('copyUrl'),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );

    if (result == 'copy_url' && context.mounted) {
      await Clipboard.setData(ClipboardData(text: target.url));
      if (context.mounted) {
        DashboardSnack.show(context, context.l10n.t('copySuccess'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tableWidth = widget.widths.total;

    return Scrollbar(
      controller: _horizontalController,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          child: Column(
            children: [
              // 表头
              _buildTableHeader(context),
              // 数据行
              Expanded(
                child: Scrollbar(
                  controller: _verticalController,
                  child: ListView.builder(
                    controller: _verticalController,
                    itemCount: widget.targets.length,
                    itemBuilder: (context, index) {
                      final target = widget.targets[index];
                      return _buildTableRow(context, target, index);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final headerStyle = textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    Widget headerCell(String label, double width) {
      return Container(
        width: width,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Text(label, style: headerStyle, overflow: TextOverflow.ellipsis),
      );
    }

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          headerCell(context.l10n.t('webpageTitle'), widget.widths.title),
          headerCell(context.l10n.t('webpageUrl'), widget.widths.url),
          headerCell(context.l10n.t('webpageType'), widget.widths.type),
        ],
      ),
    );
  }

  Widget _buildTableRow(BuildContext context, WebpageTarget target, int index) {
    final isSelected = target.id == widget.selectedId;

    // 行背景交替色
    final Color? rowColor = isSelected
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
        : index % 2 == 0
        ? null
        : Theme.of(
            context,
          ).colorScheme.surfaceContainerLowest.withValues(alpha: 0.5);

    return InkWell(
      onTap: () => widget.onSelected(target),
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition, target);
      },
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: rowColor,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // 标题
            Container(
              width: widget.widths.title,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target.title.isNotEmpty ? target.title : '无标题',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${target.packageName} (PID: ${target.pid})',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // URL
            Container(
              width: widget.widths.url,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              child: Text(
                target.url,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 类型
            Container(
              width: widget.widths.type,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text(
                  target.isAttached
                      ? context.l10n.t('webpageAttached')
                      : target.type,
                  style: const TextStyle(fontSize: 11),
                ),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
