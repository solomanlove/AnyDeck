import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/ios/ios_app_info.dart';
import '../../apps/widgets/apps_alphabet_sidebar.dart';
import '../../widgets/dashboard_table_header.dart';
import '../model/ios_apps_filter.dart';
import 'ios_app_icon_view.dart';

/// iOS 应用表格：apps 是筛选结果，totalCount 是设备应用总数。
/// favorites 按 Bundle ID 标记收藏；回调交由父页面处理持久化及卸载确认。
/// 使用固定行高虚拟列表，复用 Android 的字母索引与表头、分隔线样式。
class IosAppsTable extends StatefulWidget {
  const IosAppsTable({
    super.key,
    required this.apps,
    required this.totalCount,
    required this.favorites,
    required this.onFavorite,
    required this.onUninstall,
  });

  final List<IosAppInfo> apps;
  final int totalCount;
  final Set<String> favorites;
  final ValueChanged<IosAppInfo>? onFavorite;
  final ValueChanged<IosAppInfo>? onUninstall;

  @override
  State<IosAppsTable> createState() => _IosAppsTableState();
}

class _IosAppsTableState extends State<IosAppsTable> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  bool _ascending = true;
  bool _sortVersion = false;

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _sort(bool version) => setState(() {
    _ascending = _sortVersion == version ? !_ascending : true;
    _sortVersion = version;
  });

  void _jump(String letter, List<IosAppInfo> apps) {
    final index = apps.indexWhere((app) => iosAppFirstLetter(app) == letter);
    if (index < 0 || !_vertical.hasClients) return;
    _vertical.animateTo(
      (index * 56.0).clamp(0, _vertical.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apps = [...widget.apps]
      ..sort((a, b) {
        final left = _sortVersion ? a.version ?? '' : a.name;
        final right = _sortVersion ? b.version ?? '' : b.name;
        final result = left.toLowerCase().compareTo(right.toLowerCase());
        return _ascending ? result : -result;
      });
    final count = context.l10n
        .t('appCount')
        .replaceAll('{visible}', '${apps.length}')
        .replaceAll('{total}', '${widget.totalCount}');
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 28).clamp(600.0, double.infinity);
        return Row(
          children: [
            Expanded(
              child: Scrollbar(
                controller: _horizontal,
                notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    height: constraints.maxHeight,
                    child: Column(
                      children: [
                        Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            border: Border(
                              bottom: BorderSide(
                                color: theme.dividerColor.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              _header(
                                '${context.l10n.t('appName')} ($count)',
                                false,
                              ),
                              _header(context.l10n.t('version'), true),
                              SizedBox(
                                width: 90,
                                child: Text(
                                  context.l10n.t('appType'),
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              const SizedBox(width: 48),
                            ],
                          ),
                        ),
                        Expanded(
                          child: apps.isEmpty
                              ? Center(
                                  child: Text(context.l10n.t('noPackages')),
                                )
                              : Scrollbar(
                                  controller: _vertical,
                                  child: ListView.builder(
                                    controller: _vertical,
                                    itemExtent: 56,
                                    itemCount: apps.length,
                                    itemBuilder: (context, index) =>
                                        _row(apps[index], index),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: AppsAlphabetSidebar(
                availableLetters: apps.map(iosAppFirstLetter).toSet(),
                onLetterSelected: (letter) => _jump(letter, apps),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(String label, bool version) => DashboardSortableHeaderCell(
    label: label,
    width: version ? 150 : null,
    flex: version ? null : 1,
    onTap: () => _sort(version),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    style: Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    sortIcon: DashboardSortIcon(
      active: _sortVersion == version,
      ascending: _ascending,
    ),
  );

  Widget _row(IosAppInfo app, int index) {
    final theme = Theme.of(context);
    final favorite = widget.favorites.contains(app.bundleId);
    return Container(
      key: ValueKey(app.bundleId),
      decoration: BoxDecoration(
        color: index.isOdd
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.12)
            : null,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          IosAppIconView(
            iconPath: app.iconPath,
            bundleId: app.bundleId,
            system: app.system,
            size: 32,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        app.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  IconButton(
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                      tooltip: context.l10n.t(
                        favorite ? 'deleteFavorite' : 'addFavorite',
                      ),
                      onPressed: widget.onFavorite == null
                          ? null
                          : () => widget.onFavorite!(app),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 24,
                      ),
                      iconSize: 18,
                      icon: Icon(
                        favorite ? Icons.star : Icons.star_border,
                        color: favorite
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.5,
                              ),
                      ),
                    ),
                  ],
                ),
                Text(
                  app.bundleId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 150,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(app.version ?? '-', overflow: TextOverflow.ellipsis),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(context.l10n.t(app.system ? 'systemApp' : 'userApp')),
          ),
          IconButton(
            tooltip: context.l10n.t('uninstall'),
            onPressed: app.system || widget.onUninstall == null
                ? null
                : () => widget.onUninstall!(app),
            icon: const Icon(Icons.delete_outline),
            color: theme.colorScheme.error,
          ),
        ],
      ),
    );
  }
}
