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
    final selectedTool = ref.watch(selectedToolTabProvider);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final iconColor = isDark ? const Color(0xffb0bec5) : const Color(0xff5f6b6e);

    return DashboardHeaderBar(
      title: context.l10n.t('devices'),
      subtitle: context.l10n.t('devicesSubtitle'),
      actions: [
        //tcp连接
        IconButton(
          tooltip: context.l10n.t('connectTcp'),
          icon: const Icon(CupertinoIcons.link),
          iconSize: 30,
          color: iconColor,
          onPressed: () => _showConnectDeviceDialog(context, ref),
          style: IconButton.styleFrom(
            fixedSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        //无线连接
        IconButton(
          tooltip: context.l10n.t('pairDeviceTitle'),
          icon: const Icon(CupertinoIcons.antenna_radiowaves_left_right),
          iconSize: 30,
          color: iconColor,
          onPressed: () => showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (context) => const _DevicePairingDialog(),
          ),
          style: IconButton.styleFrom(
            fixedSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        //打开文件位置
        ToolDirectoryMenuButton(iconColor: iconColor),
        //重置服务
        ServiceRestartMenuButton(iconColor: iconColor),
        //刷新
        IconButton(
          tooltip: context.l10n.t('refreshDevices'),
          icon: const Icon(CupertinoIcons.refresh),
          iconSize: 30,
          color: iconColor,
          onPressed: () => _refreshDevices(context, ref),
          style: IconButton.styleFrom(
            fixedSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}

class _DashboardHomeContent extends ConsumerWidget {
  const _DashboardHomeContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DeviceListPanel();
  }
}