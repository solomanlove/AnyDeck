import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../model/device_workspace_view_state.dart';

/// 设备墙与列表共用的工具栏：状态筛选、自适应搜索、视图切换和批量管理。
///
/// [controller] 由父级释放；数量为筛选前的总数。所有回调仅通知父级，
/// 不扫描设备或修改选择。外层水平留白由工作区统一提供。
/// [groupFilter] 可选，展示在搜索右侧；工具栏负责宽度约束与窄屏换行。
class DeviceListFilters extends StatelessWidget {
  const DeviceListFilters({
    super.key,
    required this.controller,
    required this.onlineCount,
    required this.totalCount,
    required this.filter,
    required this.onFilterChanged,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.batchMode,
    required this.onBatchModeChanged,
    required this.onSearchChanged,
    this.groupFilter,
  });

  final TextEditingController controller;
  final int onlineCount;
  final int totalCount;
  final DeviceStatusFilter filter;
  final ValueChanged<DeviceStatusFilter> onFilterChanged;
  final DeviceViewMode viewMode;
  final ValueChanged<DeviceViewMode> onViewModeChanged;
  final bool batchMode;
  final ValueChanged<bool> onBatchModeChanged;
  final ValueChanged<String> onSearchChanged;
  final Widget? groupFilter;

  TextStyle _labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 12);

  String _filterLabel(BuildContext context, DeviceStatusFilter value) =>
      context.l10n.t(switch (value) {
        DeviceStatusFilter.all => 'deviceWorkspaceAll',
        DeviceStatusFilter.online => 'deviceWorkspaceOnline',
        DeviceStatusFilter.offline => 'deviceWorkspaceOffline',
      });

  int _count(DeviceStatusFilter value) => switch (value) {
    DeviceStatusFilter.all => totalCount,
    DeviceStatusFilter.online => onlineCount,
    DeviceStatusFilter.offline => totalCount - onlineCount,
  };

  String _manageLabel(BuildContext context) => context.l10n.t(
    batchMode ? 'deviceWorkspaceBatchExit' : 'deviceWorkspaceBatchManage',
  );

  // 按当前语言与字号测量必需空间，搜索使用剩余宽度而非固定宽度。
  double _textWidth(BuildContext context, String text, {double? size}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: _labelStyle(
          context,
        ).copyWith(fontSize: size, fontWeight: FontWeight.w600),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final filterWidth = DeviceStatusFilter.values.fold<double>(
          4,
          (width, value) =>
              width +
              22 +
              _textWidth(context, _filterLabel(context, value)) +
              _textWidth(context, '${_count(value)}', size: 11),
        );
        // 两种模式共用较宽的按钮尺寸，切换时搜索框与视图开关保持原位。
        final manageLabelWidth = max(
          _textWidth(context, context.l10n.t('deviceWorkspaceBatchManage')),
          _textWidth(context, context.l10n.t('deviceWorkspaceBatchExit')),
        );
        final manageWidth = manageLabelWidth + 18;
        final labeledViewsWidth =
            70 +
            _textWidth(context, context.l10n.t('deviceWorkspaceWall')) +
            _textWidth(context, context.l10n.t('deviceWorkspaceList'));
        const iconViewsWidth = 70.0;
        final minSearch = 160 * MediaQuery.textScalerOf(context).scale(1);
        final available = constraints.maxWidth;
        final groupWidth = groupFilter == null
            ? 0.0
            : 144 * MediaQuery.textScalerOf(context).scale(1);
        final groupSpace = groupFilter == null ? 0.0 : groupWidth + 8;
        // 搜索框两侧各留 8px，视图开关与批量按钮之间留 6px。
        const singleRowSpacing = 22.0;
        final showLabels =
            available >=
            filterWidth +
                labeledViewsWidth +
                manageWidth +
                minSearch +
                groupSpace +
                singleRowSpacing;
        final viewsWidth = showLabels ? labeledViewsWidth : iconViewsWidth;
        final singleRow =
            available >=
            filterWidth +
                viewsWidth +
                manageWidth +
                minSearch +
                groupSpace +
                singleRowSpacing;
        final filters = _buildFilters(context);
        final controls = _buildControls(context, showLabels, manageWidth);
        final search = _buildSearch(context);
        if (singleRow) {
          return Row(
            key: const Key('deviceToolbarSingleRow'),
            children: [
              filters,
              const SizedBox(width: 8),
              Expanded(child: search),
              const SizedBox(width: 8),
              if (groupFilter != null) ...[
                SizedBox(width: groupWidth, child: groupFilter),
                const SizedBox(width: 8),
              ],
              controls,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (available >= filterWidth + viewsWidth + manageWidth + 16)
              Row(children: [filters, const Spacer(), controls])
            else ...[
              filters,
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerRight, child: controls),
            ],
            const SizedBox(height: 6),
            if (groupFilter == null)
              search
            else if (available >= minSearch + groupSpace)
              Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 8),
                  SizedBox(width: groupWidth, child: groupFilter),
                ],
              )
            else ...[
              search,
              const SizedBox(height: 6),
              groupFilter!,
            ],
          ],
        );
      },
    ),
  );

  Widget _buildFilters(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: context.l10n.t('deviceWorkspaceFilter'),
      child: Wrap(
        key: const Key('deviceListCounts'),
        spacing: 2,
        runSpacing: 3,
        children: [
          for (final value in DeviceStatusFilter.values)
            Semantics(
              selected: filter == value,
              child: TextButton(
                key: Key('deviceFilter-${value.name}'),
                onPressed: () => onFilterChanged(value),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: filter == value
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  backgroundColor: filter == value
                      ? theme.deviceSelectionBackground
                      : Colors.transparent,
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppThemeSizes.radiusMedium,
                  ),
                  textStyle: _labelStyle(context).copyWith(
                    fontWeight: filter == value
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_filterLabel(context, value)),
                    const SizedBox(width: 6),
                    Text(
                      '${_count(value)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControls(
    BuildContext context,
    bool showLabels,
    double manageWidth,
  ) => Wrap(
    spacing: 6,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    alignment: WrapAlignment.end,
    children: [
      _buildViewSwitch(context, showLabels),
      Semantics(
        selected: batchMode,
        child: OutlinedButton(
          key: const Key('deviceBatchManage'),
          onPressed: () => onBatchModeChanged(!batchMode),
          style: OutlinedButton.styleFrom(
            minimumSize: Size(manageWidth, 36),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: _labelStyle(context),
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            backgroundColor: batchMode
                ? Theme.of(context).deviceSelectionBackground
                : Theme.of(context).appColors.panelSurface,
            side: BorderSide(
              color: batchMode
                  ? Theme.of(context).deviceSelectionBorder
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: AppThemeSizes.radiusMedium,
            ),
          ),
          child: Text(_manageLabel(context)),
        ),
      ),
    ],
  );

  Widget _buildViewSwitch(BuildContext context, bool showLabels) {
    final theme = Theme.of(context);
    return Semantics(
      label: context.l10n.t('deviceWorkspaceView'),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: theme.appColors.panelSurface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: AppThemeSizes.radiusMedium,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in DeviceViewMode.values)
              Tooltip(
                message: context.l10n.t(
                  mode == DeviceViewMode.wall
                      ? 'deviceWorkspaceWallView'
                      : 'deviceWorkspaceListView',
                ),
                child: Semantics(
                  selected: viewMode == mode,
                  child: TextButton(
                    key: Key('deviceView-${mode.name}'),
                    onPressed: () => onViewModeChanged(mode),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(32, 30),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: _labelStyle(context).copyWith(
                        fontWeight: viewMode == mode
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      foregroundColor: viewMode == mode
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      backgroundColor: viewMode == mode
                          ? theme.deviceSelectionBackground
                          : Colors.transparent,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppThemeSizes.radiusSmall,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          mode == DeviceViewMode.wall
                              ? LucideIcons.layoutGrid
                              : LucideIcons.list,
                          size: 14,
                        ),
                        if (showLabels) ...[
                          const SizedBox(width: 4),
                          Text(
                            context.l10n.t(
                              mode == DeviceViewMode.wall
                                  ? 'deviceWorkspaceWall'
                                  : 'deviceWorkspaceList',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch(BuildContext context) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: AppThemeSizes.radiusMedium,
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    return Tooltip(
      message: context.l10n.t('deviceListSearchHint'),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          key: const Key('deviceListSearch'),
          controller: controller,
          onChanged: onSearchChanged,
          style: _labelStyle(context),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: theme.appColors.panelSurface,
            hintText: context.l10n.t('deviceWorkspaceSearchHint'),
            hintStyle: _labelStyle(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(
                color: theme.colorScheme.onSurfaceVariant,
                width: AppThemeSizes.strongBorderWidth,
              ),
            ),
            prefixIcon: const Icon(LucideIcons.search, size: 17),
            prefixIconColor: theme.colorScheme.onSurfaceVariant,
            prefixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 36,
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            suffixIcon: value.text.isEmpty
                ? null
                : SizedBox.square(
                    dimension: 36,
                    child: IconButton(
                      tooltip: context.l10n.t('clear'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        controller.clear();
                        onSearchChanged('');
                      },
                      icon: const Icon(Icons.close_rounded, size: 16),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
