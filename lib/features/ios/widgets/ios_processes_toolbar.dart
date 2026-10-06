import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/widget/dashboard_tab_layout.dart';
import '../model/ios_processes_filter.dart';

/// 共用 Dashboard 搜索工具栏；父页面提供筛选、轮询状态和设备操作回调。
class IosProcessesToolbar extends StatelessWidget {
  const IosProcessesToolbar({
    super.key,
    required this.controller,
    required this.category,
    required this.onlyApps,
    required this.autoRefresh,
    required this.busy,
    required this.onQuery,
    required this.onCategory,
    required this.onOnlyApps,
    required this.onAutoRefresh,
    required this.onRefresh,
  });

  final TextEditingController controller;
  final IosProcessFilter category;
  final bool onlyApps, autoRefresh, busy;
  final ValueChanged<String> onQuery;
  final ValueChanged<IosProcessFilter> onCategory;
  final ValueChanged<bool> onOnlyApps, onAutoRefresh;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) =>
      DashboardSearchToolbar<IosProcessFilter>(
        narrowBreakpoint: 1100,
        searchController: controller,
        searchHint: context.l10n.t('iosProcessSearch'),
        hasSearchQuery: controller.text.isNotEmpty,
        onSearchChanged: onQuery,
        onSearchSubmitted: onQuery,
        onSearchClear: () {
          controller.clear();
          onQuery('');
        },
        searchHistory: const [],
        onSearchHistorySelected: onQuery,
        onSearchHistoryRemoved: (_) {},
        segments: {
          for (final type in IosProcessFilter.values)
            type: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                context.l10n.t(switch (type) {
                  IosProcessFilter.user => 'userProcesses',
                  IosProcessFilter.system => 'systemProcesses',
                  IosProcessFilter.all => 'allProcesses',
                }),
                style: const TextStyle(fontSize: 12),
              ),
            ),
        },
        currentSegment: category,
        onSegmentChanged: (value) {
          if (value != null) onCategory(value);
        },
        trailingActions: [
          _check(context, context.l10n.t('onlyShowApps'), onlyApps, onOnlyApps),
          _check(
            context,
            context.l10n.t('autoRefreshInterval').replaceAll('{seconds}', '3'),
            autoRefresh,
            onAutoRefresh,
          ),
          IconButton(
            tooltip: context.l10n.t('refreshProcessesTooltip'),
            onPressed: busy ? null : onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      );

  Widget _check(
    BuildContext context,
    String label,
    bool value,
    ValueChanged<bool> onChange,
  ) => InkWell(
    onTap: () => onChange(!value),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: (v) => onChange(v ?? false),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
