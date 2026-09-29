import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/widget/dashboard_tab_layout.dart';
import '../controller/ios_apps_controller.dart';
import '../model/ios_apps_filter.dart';

/// 复用 Android 搜索与分段样式。父页面持有输入控制器和分类，busy 禁用设备操作。
class IosAppsToolbar extends ConsumerWidget {
  const IosAppsToolbar({
    super.key,
    required this.controller,
    required this.category,
    required this.onQueryChanged,
    required this.onCategoryChanged,
    required this.busy,
    required this.onRefresh,
    required this.onInstall,
  });

  final TextEditingController controller;
  final IosAppFilter category;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<IosAppFilter> onCategoryChanged;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final history = ref.watch(iosAppsSearchHistoryProvider).value ?? <String>[];
    final labels = {
      IosAppFilter.user: context.l10n.t('userApps'),
      IosAppFilter.system: context.l10n.t('systemApps'),
      IosAppFilter.all: context.l10n.t('allApps'),
      IosAppFilter.favorites: context.l10n.t('favoriteApps'),
    };
    // 按当前语言和字体测量分段，给搜索框（含清除/历史按钮）保留足够宽度。
    double textWidth(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final segmentStyle = DefaultTextStyle.of(
      context,
    ).style.copyWith(fontSize: 12, fontWeight: FontWeight.w600);
    final longestSegment = labels.values
        .map((label) => textWidth(label, segmentStyle))
        .reduce(math.max);
    final installWidth = textWidth(
      context.l10n.t('iosInstallIpa'),
      theme.textTheme.labelLarge!,
    );
    return DashboardSearchToolbar<IosAppFilter>(
      narrowBreakpoint: math.max(
        760,
        (longestSegment + 28) * 4 + installWidth + 360,
      ),
      searchController: controller,
      searchHint: context.l10n.t('filterPackage'),
      hasSearchQuery: controller.text.isNotEmpty,
      onSearchChanged: onQueryChanged,
      onSearchSubmitted: (value) =>
          ref.read(iosAppsSearchHistoryProvider.notifier).add(value),
      onSearchClear: () {
        controller.clear();
        onQueryChanged('');
      },
      searchHistory: history,
      onSearchHistorySelected: (value) =>
          ref.read(iosAppsSearchHistoryProvider.notifier).add(value),
      onSearchHistoryRemoved: (value) =>
          ref.read(iosAppsSearchHistoryProvider.notifier).remove(value),
      onSearchHistoryCleared: () =>
          ref.read(iosAppsSearchHistoryProvider.notifier).clear(),
      segments: labels.map(
        (type, label) => MapEntry(
          type,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: category == type
                    ? FontWeight.w600
                    : FontWeight.normal,
                color: category == type
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
      currentSegment: category,
      onSegmentChanged: (value) {
        if (value != null) onCategoryChanged(value);
      },
      trailingActions: [
        IconButton(
          tooltip: context.l10n.t('refresh'),
          onPressed: busy ? null : onRefresh,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: busy ? null : onInstall,
          icon: const Icon(Icons.install_mobile),
          label: Text(context.l10n.t('iosInstallIpa')),
        ),
      ],
    );
  }
}
