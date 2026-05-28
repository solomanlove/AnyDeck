part of 'dashboard_screen.dart';

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
    return Row(
      children: [
        _PrimaryRail(selectedDevice: selectedDevice),
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xfffbfbfc)),
            child: Column(
              children: [
                if (selectedDevice == null) _ContentTitleBar(title: title),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryRail extends ConsumerWidget {
  const _PrimaryRail({required this.selectedDevice});

  final AdbDevice? selectedDevice;

  static const double _fullToolRailMinHeight = 704;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTool = ref.watch(selectedToolTabProvider);
    final registeredDevices = ref.watch(deviceRegistryProvider);
    final hasOnlineDevice = registeredDevices.any((d) => d.isOnline);
    final canInteract = selectedDevice != null || hasOnlineDevice;
    final tools = [
      _RailToolItem(
        tabIndex: 0,
        icon: Icons.phone_android_outlined,
        label: context.l10n.t('overview'),
      ),
      _RailToolItem(
        tabIndex: 1,
        icon: Icons.tune,
        label: context.l10n.t('control'),
      ),
      _RailToolItem(
        tabIndex: 2,
        icon: Icons.apps_outlined,
        label: context.l10n.t('apps'),
      ),
      _RailToolItem(
        tabIndex: 3,
        icon: Icons.folder_outlined,
        label: context.l10n.t('files'),
      ),
      _RailToolItem(
        tabIndex: 4,
        icon: Icons.article_outlined,
        label: context.l10n.t('logcat'),
      ),
      _RailToolItem(
        tabIndex: 5,
        icon: Icons.terminal_outlined,
        label: context.l10n.t('terminal'),
      ),
      _RailToolItem(
        tabIndex: 6,
        icon: Icons.analytics_outlined,
        label: context.l10n.t('processes'),
      ),
      _RailToolItem(
        tabIndex: 7,
        icon: Icons.web_outlined,
        label: context.l10n.t('webpages'),
      ),
    ];

    void handleTap(int tabIndex) {
      var device = selectedDevice;
      if (device == null) {
        // Find the first online device
        RegisteredDevice? firstOnline;
        for (final d in registeredDevices) {
          if (d.isOnline) {
            firstOnline = d;
            break;
          }
        }
        if (firstOnline != null) {
          device = firstOnline.toAdbDevice;
          ref.read(userClearedDeviceSelectionProvider.notifier).state = false;
          ref.read(selectedDeviceProvider.notifier).select(device);
        }
      }
      if (device != null) {
        ref.read(selectedToolTabProvider.notifier).select(tabIndex);
      }
    }

    return Container(
      width: 76,
      color: const Color(0xffd8f3f5),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hideToolButtons =
                constraints.maxHeight < _fullToolRailMinHeight;

            return Column(
              children: [
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () {
                    ref
                            .read(userClearedDeviceSelectionProvider.notifier)
                            .state =
                        true;
                    ref.read(selectedDeviceProvider.notifier).clear();
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      width: 42,
                      height: 42,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Image(
                        image: AssetImage('assets/brand/app_logo.png'),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: hideToolButtons ? 18 : 28),
                if (hideToolButtons)
                  _RailMoreButton(
                    tools: tools,
                    hasSelectedDevice: selectedDevice != null,
                    selectedTool: selectedTool,
                    enabled: canInteract,
                    onSelected: handleTap,
                  )
                else
                  for (final tool in tools)
                    _RailButton(
                      icon: tool.icon,
                      selected:
                          selectedDevice != null &&
                          selectedTool == tool.tabIndex,
                      tooltip: tool.label,
                      onPressed: canInteract
                          ? () => handleTap(tool.tabIndex)
                          : null,
                    ),
                const Spacer(),
                _RailButton(
                  icon: Icons.settings_outlined,
                  tooltip: context.l10n.t('settings'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const _SettingsDialog(),
                  ),
                ),
                const SizedBox(height: 18),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RailToolItem {
  const _RailToolItem({
    required this.tabIndex,
    required this.icon,
    required this.label,
  });

  final int tabIndex;
  final IconData icon;
  final String label;
}

class _RailMoreButton extends StatelessWidget {
  const _RailMoreButton({
    required this.tools,
    required this.hasSelectedDevice,
    required this.selectedTool,
    required this.enabled,
    required this.onSelected,
  });

  final List<_RailToolItem> tools;
  final bool hasSelectedDevice;
  final int selectedTool;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected =
        hasSelectedDevice && tools.any((tool) => tool.tabIndex == selectedTool);
    final color = selected ? const Color(0xff09c47c) : const Color(0xff5f6b6e);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: PopupMenuButton<int>(
        tooltip: context.l10n.t('moreTools'),
        onSelected: enabled ? onSelected : null,
        itemBuilder: (context) => [
          for (final tool in tools)
            PopupMenuItem<int>(
              value: tool.tabIndex,
              enabled: enabled,
              child: Row(
                children: [
                  Icon(
                    tool.icon,
                    size: 20,
                    color: tool.tabIndex == selectedTool
                        ? const Color(0xff09c47c)
                        : const Color(0xff5f6b6e),
                  ),
                  const SizedBox(width: 12),
                  Text(tool.label),
                ],
              ),
            ),
        ],
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.56)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.more_horiz, size: 28, color: color),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    this.selected = false,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xff09c47c) : const Color(0xff5f6b6e);

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: IconButton(
          icon: Icon(icon),
          color: color,
          iconSize: 28,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: selected
                ? Colors.white.withValues(alpha: 0.56)
                : Colors.transparent,
            disabledForegroundColor: const Color(0xff8b9a9e),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContentTitleBar extends ConsumerWidget {
  const _ContentTitleBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffeceef1), width: 1)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xff202124),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: context.l10n.t('restartAdb'),
            icon: const Icon(Icons.adb),
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
    );
  }
}

class _DashboardHomeContent extends StatelessWidget {
  const _DashboardHomeContent();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        _DeviceListPanel(),
        SizedBox(height: 16),
        _EmulatorListPanel(),
      ],
    );
  }
}

/// 设置弹窗表单，用于切换语言和主题。
