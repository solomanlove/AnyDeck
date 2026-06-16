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
    final isDark = theme.brightness == Brightness.dark;

    final glassBgColor = isDark
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.28);
    final glassBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.04);

    return LiquidGlassBackground(
      child: Row(
        children: [
          _PrimaryRail(selectedDevice: selectedDevice),
          Expanded(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: glassBgColor,
                    border: Border(
                      left: BorderSide(color: glassBorderColor, width: 1),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (selectedDevice == null && selectedTool != 12)
                        _ContentTitleBar(title: title),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentTitleBar extends ConsumerWidget {
  const _ContentTitleBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final titleColor = isDark ? const Color(0xffeceff1) : const Color(0xff202124);
    final iconColor = isDark ? const Color(0xffb0bec5) : const Color(0xff5f6b6e);

    return DragToMoveArea(
      child: GlassmorphicContainer(
        width: double.infinity,
        height: 72,
        borderRadius: 0,
        blur: 15,
        alignment: Alignment.center,
        border: 0,
        linearGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.40),
            isDark ? Colors.white.withValues(alpha: 0.01) : Colors.white.withValues(alpha: 0.15),
          ],
        ),
        borderGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
            isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.03),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              const Image(
                image: AssetImage(AppIcons.appLogo),
                width: 28,
                height: 28,
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                ),
              ),
              const Spacer(),
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
              const SizedBox(width: 8),
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
              const SizedBox(width: 8),
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
              const SizedBox(width: 8),
              IconButton(
                tooltip: context.l10n.t('terminalDir'),
                icon: const Icon(Icons.terminal),
                iconSize: 30,
                color: iconColor,
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
                color: iconColor,
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
              const SizedBox(width: 8),
              IconButton(
                tooltip: context.l10n.t('restartAdb'),
                icon: const Icon(CupertinoIcons.ant),
                iconSize: 30,
                color: iconColor,
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
      ),
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
