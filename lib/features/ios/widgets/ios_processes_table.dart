import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/ios/ios_process_info.dart';
import '../../widgets/dashboard_table_header.dart';
import '../model/ios_processes_filter.dart';
import 'ios_app_icon_view.dart';

/// 固定行高虚拟表格；items 已筛选排序，onMenu 由页面负责复制、详情和结束确认。
/// 仅真实字段可排序，未知指标保留可解释的占位，不以零值参与排序。
class IosProcessesTable extends StatefulWidget {
  const IosProcessesTable({
    super.key,
    required this.items,
    required this.total,
    required this.sort,
    required this.ascending,
    required this.onSort,
    required this.onMenu,
  });
  final List<IosProcessInfo> items;
  final int total;
  final IosProcessSort sort;
  final bool ascending;
  final ValueChanged<IosProcessSort> onSort;
  final void Function(IosProcessInfo, Offset) onMenu;

  @override
  State<IosProcessesTable> createState() => _IosProcessesTableState();
}

class _IosProcessesTableState extends State<IosProcessesTable> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  int? _selectedPid;

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = box.maxWidth.clamp(1080.0, double.infinity);
      final nameWidth = width - 740;
      return Scrollbar(
        controller: _horizontal,
        notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: box.maxHeight,
            child: Column(
              children: [
                Container(
                  height: 48,
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  child: Row(
                    children: [
                      _header(
                        '${context.l10n.t('processName')} (${context.l10n.t('iosProcessVisibleCount').replaceAll('{visible}', '${widget.items.length}').replaceAll('{total}', '${widget.total}')})',
                        nameWidth,
                        IosProcessSort.name,
                      ),
                      for (final key in ['cpuPercent', 'cpuTime', 'memory'])
                        _cell(context.l10n.t(key), 100),
                      _header(context.l10n.t('pid'), 80, IosProcessSort.pid),
                      _header(
                        context.l10n.t('appType'),
                        130,
                        IosProcessSort.type,
                      ),
                      _header(
                        context.l10n.t('iosProcessStartedAt'),
                        190,
                        IosProcessSort.startedAt,
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
                Expanded(
                  child: widget.items.isEmpty
                      ? Center(
                          child: Text(context.l10n.t('noMatchingProcesses')),
                        )
                      : Scrollbar(
                          controller: _vertical,
                          child: ListView.builder(
                            controller: _vertical,
                            itemExtent: 60,
                            itemCount: widget.items.length,
                            itemBuilder: (context, index) =>
                                _row(widget.items[index], index, nameWidth),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _header(String text, double width, IosProcessSort column) =>
      DashboardSortableHeaderCell(
        label: text,
        onTap: () => widget.onSort(column),
        width: width,
        height: 48,
        style: Theme.of(context).textTheme.titleSmall,
        sortIcon: DashboardSortIcon(
          active: widget.sort == column,
          ascending: widget.ascending,
        ),
      );

  Widget _cell(String text, double width) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ),
  );

  Widget _row(IosProcessInfo item, int index, double nameWidth) {
    final scheme = Theme.of(context).colorScheme;
    final app = item.app;
    final bundle = item.bundleId ?? app?.bundleId;
    final subtitle = item.isExtension && app != null && item.bundleId == null
        ? '${context.l10n.t('iosProcessHostBundleId')}: ${app.bundleId}'
        : bundle ?? item.executablePath ?? context.l10n.t('iosProcessUnknown');
    return InkWell(
      key: ValueKey('ios-process-${item.pid}'),
      onTap: () => setState(() => _selectedPid = item.pid),
      onSecondaryTapDown: (details) =>
          widget.onMenu(item, details.globalPosition),
      child: Container(
        decoration: BoxDecoration(
          color: _selectedPid == item.pid
              ? scheme.primaryContainer.withValues(alpha: 0.4)
              : index.isOdd
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.12)
              : null,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: nameWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    IosAppIconView(
                      iconPath: app?.iconPath,
                      bundleId: app?.bundleId ?? '',
                      system: app?.system ?? false,
                      size: 30,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Tooltip(
                        message: [
                          item.displayName,
                          subtitle,
                          if (item.isExtension)
                            context.l10n.t('iosProcessExtension'),
                          if (item.isExtension && app != null)
                            '${context.l10n.t('iosProcessHostBundleId')}: ${app.bundleId}',
                          if (item.executablePath != null) item.executablePath!,
                        ].join('\n'),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (var i = 0; i < 3; i++)
              _cell(context.l10n.t('iosProcessNotCollected'), 100),
            _cell('${item.pid}', 80),
            _cell(context.l10n.t(iosProcessTypeKey(item)), 130),
            _cell(
              item.startedAt
                      ?.toLocal()
                      .toIso8601String()
                      .split('.')
                      .first
                      .replaceFirst('T', ' ') ??
                  context.l10n.t('iosProcessNotCollected'),
              190,
            ),
            SizedBox(
              width: 40,
              child: Builder(
                builder: (context) => IconButton(
                  tooltip: context.l10n.t('iosProcessActions'),
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () {
                    final box = context.findRenderObject()! as RenderBox;
                    widget.onMenu(
                      item,
                      box.localToGlobal(Offset(0, box.size.height)),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
