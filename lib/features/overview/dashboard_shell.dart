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
    final compact = MediaQuery.sizeOf(context).width <= 490;
    // 窄窗口放大字体时，连接入口以图标和 Tooltip 提供。
    final showConnectionLabel =
        !compact || MediaQuery.textScalerOf(context).scale(13) <= 16;
    // 复用一级页面标题规范；窄窗口额外避让原生窗口按钮。
    return DashboardHeaderBar(
      key: const Key('deviceManagementHeader'),
      title: context.l10n.t('devices'),
      subtitle: context.l10n.t('deviceWorkspaceSubtitle'),
      padding: compact
          ? const EdgeInsets.fromLTRB(10, 32, 10, 12)
          : const EdgeInsets.symmetric(horizontal: 28),
      actions: [
        IconButton(
          tooltip: context.l10n.t('refreshDevices'),
          icon: const Icon(LucideIcons.refreshCw, size: 17),
          onPressed: () async {
            await _refreshDevices(context, ref);
            if (context.mounted) refreshVisibleDeviceScreenPreviews(ref);
          },
        ),
        DeviceConnectionMenu(
          showLabel: showConnectionLabel,
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
        ),
      ],
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
