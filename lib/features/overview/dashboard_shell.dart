part of '../dashboard_screen.dart';

class _WechatStyleShell extends ConsumerWidget {
  const _WechatStyleShell({
    required this.title,
    required this.selectedDevice,
    required this.isAirplayReceiverRunning,
    required this.child,
  });

  final String title;
  final DiscoveredDevice? selectedDevice;
  final bool isAirplayReceiverRunning;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 主窗口常驻所有者，恢复 Wi-Fi 自动准备规则不依赖打开设备管理或共享弹窗。
    ref.watch(deviceShareServiceProvider);
    final selectedTool = ref.watch(selectedToolTabProvider);
    final baseTheme = Theme.of(context);
    return Theme(
      data: selectedTool == -1 ? buildDeviceWorkspaceTheme(baseTheme) : baseTheme,
      child: Builder(
        builder: (context) => _buildWorkspace(context, selectedTool),
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context, int selectedTool) {
    final theme = Theme.of(context);

    return Row(
      children: [
        _PrimaryRail(
          selectedDevice: selectedDevice,
          isAirplayReceiverRunning: isAirplayReceiverRunning,
        ),
        Expanded(
          child: DesktopWorkspaceSurface(
            border: Border(
              left: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ConsoleDock(
                    child: Column(
                      children: [
                        if ((selectedDevice == null || selectedTool == -1) &&
                            selectedTool != -2 &&
                            selectedTool != -3 &&
                            selectedTool != -4 &&
                            selectedTool != -5 &&
                            selectedTool != 12 &&
                            selectedTool != 13 &&
                            selectedTool != 14)
                          _ContentTitleBar(title: title),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ),
                const HostNetworkFooter(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ContentTitleBar extends ConsumerWidget {
  const _ContentTitleBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width <= 490;
    // 窄窗口放大字体时保留完整标题，连接入口以图标和 Tooltip 提供。
    final showConnectionLabel =
        !compact || MediaQuery.textScalerOf(context).scale(13) <= 16;
    return DragToMoveArea(
      child: Container(
        key: const Key('deviceManagementHeader'),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          compact ? 10 : 16,
          compact ? 32 : 16,
          compact ? 10 : 16,
          12,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.t('devices'),
                    style: TextStyle(
                      fontSize: compact ? 18 : 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.t('deviceWorkspaceSubtitle'),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: context.l10n.t('refreshDevices'),
              icon: const Icon(LucideIcons.refreshCw, size: 17),
              onPressed: () async {
                await _refreshDevices(context, ref);
                if (context.mounted) refreshVisibleDeviceScreenPreviews(ref);
              },
            ),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              tooltip: context.l10n.t('deviceWorkspaceConnect'),
              onSelected: (action) {
                switch (action) {
                  case 'tcp':
                    _showConnectDeviceDialog(context, ref);
                  case 'pair':
                    showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const _DeviceWirelessConnectionDialog(),
                    );
                  case 'share':
                    showDialog<void>(
                      context: context,
                      builder: (_) => const DeviceShareDialog(),
                    );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'pair',
                  child: Text(context.l10n.t('deviceWorkspacePair')),
                ),
                PopupMenuItem(
                  value: 'tcp',
                  child: Text(context.l10n.t('deviceWorkspaceConnectIp')),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: Text(context.l10n.t('deviceShareJoin')),
                ),
                PopupMenuItem(enabled: false,
                  child: Text(context.l10n.t('deviceWorkspaceUsbHint'),
                    style: const TextStyle(fontSize: 11))),
              ],
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: AppThemeSizes.radiusMedium,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.plus,
                        size: 17,
                        color: theme.colorScheme.onPrimary,
                      ),
                      if (showConnectionLabel) ...[
                        const SizedBox(width: 7),
                        Text(
                          context.l10n.t('deviceWorkspaceConnect'),
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onPrimary,
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
}

class _DashboardHomeContent extends ConsumerWidget {
  const _DashboardHomeContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(color: Theme.of(context).appColors.sunkenSurface,
      child: const _DeviceListPanel());
  }
}
