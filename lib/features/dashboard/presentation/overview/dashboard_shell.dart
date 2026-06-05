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
    return Row(
      children: [
        _PrimaryRail(selectedDevice: selectedDevice),
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xfffbfbfc)),
            child: Column(
              children: [
                if (selectedDevice == null && selectedTool != 12)
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
    return DragToMoveArea(
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Color(0xffeceef1), width: 1),
          ),
        ),
        child: Row(
          children: [
            const Image(
              image: AssetImage('assets/brand/app_logo.png'),
              width: 28,
              height: 28,
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xff202124),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: context.l10n.t('connectTcp'),
              icon: const Icon(CupertinoIcons.link),
              iconSize: 30,
              color: const Color(0xff5f6b6e),
              onPressed: () => _showConnectDeviceDialog(context, ref),
              style: IconButton.styleFrom(
                fixedSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: context.l10n.t('pairDeviceTitle'),
              icon: const Icon(CupertinoIcons.antenna_radiowaves_left_right),
              iconSize: 30,
              color: const Color(0xff5f6b6e),
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
            const SizedBox(width: 8),
            IconButton(
              tooltip: context.l10n.t('refreshDevices'),
              icon: const Icon(CupertinoIcons.refresh),
              iconSize: 30,
              color: const Color(0xff5f6b6e),
              onPressed: () => _refreshDevices(context, ref),
              style: IconButton.styleFrom(
                fixedSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: context.l10n.t('terminalDir'),
              icon: const Icon(Icons.terminal),
              iconSize: 30,
              color: const Color(0xff5f6b6e),
              onPressed: () => _openLocalTerminal(context, ref),
              style: IconButton.styleFrom(
                fixedSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: context.l10n.t('emulators'),
              icon: const Icon(CupertinoIcons.device_desktop),
              iconSize: 30,
              color: const Color(0xff5f6b6e),
              onPressed: () => EmulatorListPanel.openStandaloneWindow(context),
              style: IconButton.styleFrom(
                fixedSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: context.l10n.t('restartAdb'),
              icon: const Icon(CupertinoIcons.ant),
              iconSize: 30,
              color: const Color(0xff5f6b6e),
              onPressed: () => _restartAdbServer(context, ref),
              style: IconButton.styleFrom(
                fixedSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [_DeviceListPanel()],
    );
  }
}

/// 设置弹窗表单，用于切换语言和主题。
