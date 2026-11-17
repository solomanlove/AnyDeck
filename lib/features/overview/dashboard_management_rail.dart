part of '../dashboard_screen.dart';

/// 一级管理页侧栏按原型收口，设备工作台继续使用原有平台工具导航。
class _ManagementRail extends ConsumerWidget {
  const _ManagementRail({
    required this.tools,
    required this.selectedTool,
    required this.onSelected,
    required this.receiverRunning,
  });

  final List<_RailToolItem> tools;
  final int selectedTool;
  final ValueChanged<int> onSelected;
  final bool receiverRunning;

  IconData _toolIcon(_RailToolItem tool) => switch (tool.tabIndex) {
    -1 => LucideIcons.tabletSmartphone,
    -2 => LucideIcons.monitor,
    -3 => LucideIcons.cast,
    -4 => LucideIcons.share2,
    -5 => LucideIcons.layers,
    _ => tool.icon,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windowWidth = MediaQuery.sizeOf(context).width;
    if (windowWidth <= 490) return const SizedBox.shrink();
    final compact = windowWidth <= 850;
    final theme = Theme.of(context);
    final mcpRunning = ref.watch(mcpServerProvider.select((s) => s.isRunning));
    final consoleOpen = ref.watch(consoleDockProvider.select((s) => s.isOpen));
    final bottom = [
      (
        LucideIcons.circleHelp,
        'wanAndroid',
        selectedTool == 13,
        () => context.goNamed(AppRouteNames.wanAndroid),
      ),
      (
        LucideIcons.sparkles,
        'aiMcp',
        selectedTool == 14,
        () => context.goNamed(AppRouteNames.mcp),
      ),
      (
        LucideIcons.scrollText,
        'console',
        consoleOpen,
        ref.read(consoleDockProvider.notifier).toggle,
      ),
      (
        LucideIcons.settings,
        'settings',
        selectedTool == 12,
        () => context.goNamed(AppRouteNames.settings),
      ),
    ];
    return Container(
      key: const Key('deviceManagementRail'),
      width: compact ? 64 : 166,
      padding: EdgeInsets.fromLTRB(compact ? 10 : 12, 0, compact ? 10 : 12, 16),
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DragToMoveArea(
            child: Padding(
              padding: EdgeInsets.only(
                top: DesktopChromePolicy.current.sidebarTopInset + 20,
                bottom: 27,
              ),
              child: GestureDetector(
                onTap: () => onSelected(-1),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Row(
                    mainAxisAlignment: compact
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: AppThemeSizes.radiusMedium,
                        child: const Image(
                          image: AssetImage(AppIcons.appLogo),
                          width: 33,
                          height: 37,
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.l10n.t('appTitle'),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              Text(
                                context.l10n.t('appTagline'),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final tool in tools)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: tool.tabIndex == -3
                          ? ListenableBuilder(
                              listenable: DlnaRendererService.instance,
                              builder: (_, _) => _ManagementRailButton(
                                icon: _toolIcon(tool),
                                label: tool.label,
                                compact: compact,
                                selected: selectedTool == tool.tabIndex,
                                running:
                                    receiverRunning ||
                                    DlnaRendererService.instance.isRunning,
                                onPressed: () => onSelected(tool.tabIndex),
                              ),
                            )
                          : tool.tabIndex == -4 &&
                                AnyDeckBuildFeatures.shareCore
                          ? ListenableBuilder(
                              listenable: ref.watch(
                                harmonyShareServiceProvider,
                              ),
                              builder: (_, _) {
                                final service = ref.read(
                                  harmonyShareServiceProvider,
                                );
                                return _ManagementRailButton(
                                  icon: _toolIcon(tool),
                                  label: tool.label,
                                  compact: compact,
                                  selected: selectedTool == tool.tabIndex,
                                  running:
                                      service.enabled &&
                                      service.error == null &&
                                      (service.scanning || service.busy),
                                  onPressed: () => onSelected(tool.tabIndex),
                                );
                              },
                            )
                          : _ManagementRailButton(
                              icon: _toolIcon(tool),
                              label: tool.label,
                              compact: compact,
                              selected: selectedTool == tool.tabIndex,
                              onPressed: () => onSelected(tool.tabIndex),
                            ),
                    ),
                ],
              ),
            ),
          ),
          for (final item in bottom)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _ManagementRailButton(
                icon: item.$1,
                label: context.l10n.t(item.$2),
                compact: compact,
                selected: item.$3,
                running: item.$2 == 'aiMcp' && mcpRunning,
                onPressed: item.$4,
              ),
            ),
        ],
      ),
    );
  }
}

/// 管理侧栏复用同一点击面积、选中态和服务状态圆点。
class _ManagementRailButton extends StatelessWidget {
  const _ManagementRailButton({
    required this.icon,
    required this.label,
    required this.compact,
    required this.selected,
    required this.onPressed,
    this.running = false,
  });
  final IconData icon;
  final String label;
  final bool compact;
  final bool selected;
  final bool running;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: Material(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
          borderRadius: AppThemeSizes.radiusMedium,
          child: InkWell(
            onTap: onPressed,
            borderRadius: AppThemeSizes.radiusMedium,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 0 : 10,
                vertical: 12,
              ),
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(icon, size: 17, color: foreground),
                  if (!compact) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: foreground,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                  if (running)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.circle,
                        size: 5,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
