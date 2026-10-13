part of '../dashboard_screen.dart';

class _WechatStyleShell extends ConsumerWidget {
  const _WechatStyleShell({
    required this.title,
    required this.selectedDevice,
    required this.child,
  });

  final String title;
  final AdbDevice? selectedDevice;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTool = ref.watch(selectedToolTabProvider);
    final theme = Theme.of(context);

    return Row(
      children: [
        _PrimaryRail(selectedDevice: selectedDevice),
        Expanded(
          child: DesktopWorkspaceSurface(
            border: Border(
              left: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                if ((selectedDevice == null || selectedTool == -1) &&
                    selectedTool != -2 &&
                    selectedTool != 12 &&
                    selectedTool != 13 &&
                    selectedTool != 14)
                  _ContentTitleBar(title: title),
                Expanded(child: child),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final iconColor = isDark ? const Color(0xffb0bec5) : const Color(0xff5f6b6e);

    return DashboardHeaderBar(
      title: context.l10n.t('devices'),
      subtitle: context.l10n.t('devicesSubtitle'),
      icon: Icons.devices_rounded,
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
        //ios投屏
        AirPlayToolbarButton(iconColor: iconColor),
        //打开控制台
        IconButton(
          tooltip: context.l10n.t('console'),
          icon: const Icon(CupertinoIcons.doc_plaintext),
          iconSize: 30,
          color: iconColor,
          onPressed: () => _openConsoleWindow(context),
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

Future<void> _openConsoleWindow(BuildContext context) async {
  final title = context.l10n.t('console');
  try {
    await createAdbManageWindow(
      arguments: const {'type': 'console'},
      frame: const Offset(150, 150) & const Size(850, 550),
      title: title,
    );
  } catch (e) {
    debugPrint('Failed to open console window: $e');
  }
}

class _DashboardHomeContent extends ConsumerWidget {
  const _DashboardHomeContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DeviceListPanel();
  }
}

/// 设置弹窗表单，用于切换语言和主题。
