part of '../dashboard_screen.dart';

/// 固定在侧边栏底部的全局工具；控制台仅切换面板，不导航或清空设备选择。
class _DashboardRailFooter extends ConsumerWidget {
  const _DashboardRailFooter({required this.isNarrow});

  final bool isNarrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTool = ref.watch(selectedToolTabProvider);
    final consoleOpen = ref.watch(
      consoleDockProvider.select((state) => state.isOpen),
    );
    final mcpRunning = ref.watch(
      mcpServerProvider.select((state) => state.isRunning),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RailButton(
          icon: CupertinoIcons.question_circle,
          isFooter: true,
          tooltip: context.l10n.t('wanAndroid'),
          isNarrow: isNarrow,
          selected: selectedTool == 13,
          onPressed: () => context.goNamed(AppRouteNames.wanAndroid),
        ),
        _RailButton(
          icon: CupertinoIcons.sparkles,
          isFooter: true,
          tooltip: context.l10n.t('aiMcp'),
          isNarrow: isNarrow,
          selected: selectedTool == 14,
          statusColor: mcpRunning ? Theme.of(context).colorScheme.primary : null,
          onPressed: () => context.goNamed(AppRouteNames.mcp),
        ),
        _RailButton(
          icon: CupertinoIcons.doc_plaintext,
          isFooter: true,
          tooltip: context.l10n.t('console'),
          isNarrow: isNarrow,
          selected: consoleOpen,
          onPressed: ref.read(consoleDockProvider.notifier).toggle,
        ),
        _RailButton(
          icon: CupertinoIcons.settings,
          isFooter: true,
          tooltip: context.l10n.t('settings'),
          isNarrow: isNarrow,
          selected: selectedTool == 12,
          onPressed: () => context.goNamed(AppRouteNames.settings),
        ),
      ],
    );
  }
}
