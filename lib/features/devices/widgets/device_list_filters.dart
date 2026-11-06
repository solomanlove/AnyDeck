import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme.dart';

/// 设备列表筛选栏：左侧展示数量，右侧搜索与筛选，窄窗口分行显示。
///
/// [controller] 由宿主持有和释放；[onlineCount]、[totalCount] 是筛选前的数量。
/// [onlineOnly] 与两个回调复用设备列表状态，不触发设备扫描或持久化。
class DeviceListFilters extends StatelessWidget {
  const DeviceListFilters({
    super.key,
    required this.controller,
    required this.onlineCount,
    required this.totalCount,
    required this.onlineOnly,
    required this.onOnlineOnlyChanged,
    required this.onSearchChanged,
  });

  final TextEditingController controller;
  final int onlineCount;
  final int totalCount;
  final bool onlineOnly;
  final ValueChanged<bool> onOnlineOnlyChanged;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        // 放大文字时提前分行，避免英文状态与搜索框争抢横向空间。
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final summary = _buildSummary(context);
        final controls = _buildControls(context, textScale);
        if (constraints.maxWidth < 820 * textScale) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [summary, const SizedBox(height: 12), controls],
          );
        }
        return Row(
          children: [
            Expanded(child: summary),
            const SizedBox(width: 24),
            SizedBox(width: 480 * textScale, child: controls),
          ],
        );
      },
    ),
  );

  Widget _buildSummary(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final offlineCount = totalCount - onlineCount;
    return Semantics(
      label: l10n
          .t('deviceListSummary')
          .replaceAll('{online}', '$onlineCount')
          .replaceAll('{offline}', '$offlineCount')
          .replaceAll('{total}', '$totalCount'),
      excludeSemantics: true,
      child: Wrap(
        key: const Key('deviceListCounts'),
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              l10n
                  .t('deviceListTotalCount')
                  .replaceAll('{count}', '$totalCount'),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _DeviceStatusBadge(
            label: l10n
                .t('deviceListOnlineCount')
                .replaceAll('{count}', '$onlineCount'),
            foreground: theme.colorScheme.onPrimaryContainer,
            background: theme.colorScheme.primaryContainer,
            dotColor: theme.appColors.success,
          ),
          _DeviceStatusBadge(
            label: l10n
                .t('deviceListOfflineCount')
                .replaceAll('{count}', '$offlineCount'),
            foreground: theme.colorScheme.onSurfaceVariant,
            background: theme.appColors.subtleSurface,
            dotColor: theme.appColors.faintForeground,
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, double textScale) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final search = _buildSearch(context);
          final filter = _buildOnlineFilter(context);
          if (constraints.maxWidth < 360 * textScale) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: filter),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              filter,
            ],
          );
        },
      );

  Widget _buildSearch(BuildContext context) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: AppThemeSizes.radiusLarge,
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
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: theme.appColors.panelSurface,
            hintText: context.l10n.t('deviceListSearchLabel'),
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: AppThemeSizes.strongBorderWidth,
              ),
            ),
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            prefixIconColor: theme.colorScheme.onSurfaceVariant,
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: context.l10n.t('clear'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      controller.clear();
                      onSearchChanged('');
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildOnlineFilter(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      key: const Key('deviceListOnlineOnly'),
      label: Text(context.l10n.t('deviceListOnlineOnly')),
      avatar: Icon(
        Icons.filter_list_rounded,
        size: 18,
        color: onlineOnly ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      ),
      selected: onlineOnly,
      showCheckmark: false,
      onSelected: onOnlineOnlyChanged,
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: onlineOnly ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      ),
      backgroundColor: Theme.of(context).appColors.panelSurface,
      selectedColor: scheme.primaryContainer,
      checkmarkColor: scheme.onPrimaryContainer,
      side: BorderSide(
        color: onlineOnly ? scheme.primary : scheme.outlineVariant,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: AppThemeSizes.radiusLarge,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// 数量状态标签统一圆点、留白与文字样式；使用文字而非仅靠颜色表达状态。
class _DeviceStatusBadge extends StatelessWidget {
  const _DeviceStatusBadge({
    required this.label,
    required this.foreground,
    required this.background,
    required this.dotColor,
  });

  final String label;
  final Color foreground;
  final Color background;
  final Color dotColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: background,
      borderRadius: AppThemeSizes.radiusMedium,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 6, color: dotColor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}
