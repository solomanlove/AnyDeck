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

  static double get _topSpacing => Platform.isMacOS ? 36.0 : 14.0;
  static const double _logoSize = 50;
  static const double _fullLogoToolGap = 10;
  static const double _compactLogoToolGap = 6;
  static const double _toolSlotHeight = 60;
  static const double _settingsSlotHeight = 60;
  static const double _bottomSpacing = 18;

  int _visibleToolCount(double railHeight, int toolCount) {
    final fullAvailable =
        railHeight -
        _topSpacing -
        _logoSize -
        _fullLogoToolGap -
        _settingsSlotHeight -
        _bottomSpacing;
    final fullSlots = fullAvailable ~/ _toolSlotHeight;
    if (fullSlots >= toolCount) {
      return toolCount;
    }

    final compactAvailable =
        railHeight -
        _topSpacing -
        _logoSize -
        _compactLogoToolGap -
        _settingsSlotHeight -
        _bottomSpacing;
    final compactSlots = compactAvailable ~/ _toolSlotHeight;
    if (compactSlots <= 1) {
      return 0;
    }
    return min(toolCount, compactSlots - 1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTool = ref.watch(selectedToolTabProvider);
    final registeredDevices = ref.watch(deviceRegistryProvider);
    final hasOnlineDevice = registeredDevices.any((d) => d.isOnline);
    final canInteract = selectedDevice != null || hasOnlineDevice;
    final tools = [
      _RailToolItem(
        tabIndex: 0,
        icon: CupertinoIcons.device_phone_portrait,
        label: context.l10n.t('overview'),
      ),
      _RailToolItem(
        tabIndex: 1,
        icon: CupertinoIcons.slider_horizontal_3,
        label: context.l10n.t('control'),
      ),
      _RailToolItem(
        tabIndex: 2,
        icon: CupertinoIcons.square_grid_2x2,
        label: context.l10n.t('apps'),
      ),
      _RailToolItem(
        tabIndex: 3,
        icon: CupertinoIcons.folder,
        label: context.l10n.t('files'),
      ),
      _RailToolItem(
        tabIndex: 4,
        icon: CupertinoIcons.doc_text,
        label: context.l10n.t('logcat'),
      ),
      _RailToolItem(
        tabIndex: 5,
        icon: CupertinoIcons.chevron_left_slash_chevron_right,
        label: context.l10n.t('terminal'),
      ),
      _RailToolItem(
        tabIndex: 6,
        icon: CupertinoIcons.list_bullet,
        label: context.l10n.t('processes'),
      ),
      _RailToolItem(
        tabIndex: 7,
        icon: CupertinoIcons.globe,
        label: context.l10n.t('webpages'),
      ),
      _RailToolItem(
        tabIndex: 8,
        icon: CupertinoIcons.square_stack_3d_up,
        label: context.l10n.t('layout'),
      ),
      _RailToolItem(
        tabIndex: 9,
        icon: CupertinoIcons.camera,
        label: context.l10n.t('screenshot'),
      ),
      _RailToolItem(
        tabIndex: 10,
        icon: CupertinoIcons.speedometer,
        label: context.l10n.t('performance'),
      ),
      _RailToolItem(
        tabIndex: 11,
        icon: CupertinoIcons.wifi,
        label: context.l10n.t('network'),
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
      color: const Color(0xffe1e4e5),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final visibleToolCount = _visibleToolCount(
              constraints.maxHeight,
              tools.length,
            );
            final visibleTools = tools.take(visibleToolCount).toList();
            final overflowTools = tools.skip(visibleToolCount).toList();
            final hasOverflowTools = overflowTools.isNotEmpty;

            return Column(
              children: [
                DragToMoveArea(
                  child: Container(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: _topSpacing),
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
                            child: SizedBox(
                              width: _logoSize,
                              height: _logoSize,
                              child: const Image(
                                image: AssetImage('assets/brand/app_logo.png'),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: hasOverflowTools
                              ? _compactLogoToolGap
                              : _fullLogoToolGap,
                        ),
                      ],
                    ),
                  ),
                ),
                for (final tool in visibleTools)
                  _RailButton(
                    icon: tool.icon,
                    selected:
                        selectedDevice != null && selectedTool == tool.tabIndex,
                    tooltip: tool.label,
                    onPressed: canInteract
                        ? () => handleTap(tool.tabIndex)
                        : null,
                  ),
                if (hasOverflowTools)
                  _RailMoreButton(
                    tools: overflowTools,
                    hasSelectedDevice: selectedDevice != null,
                    selectedTool: selectedTool,
                    enabled: canInteract,
                    onSelected: handleTap,
                  ),
                const Spacer(),
                _RailButton(
                  icon: CupertinoIcons.settings,
                  tooltip: context.l10n.t('settings'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const _SettingsDialog(),
                  ),
                ),
                const SizedBox(height: _bottomSpacing),
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
        offset: const Offset(66, 0),
        color: const Color(0xfff5f6f8),
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xffeceef1), width: 1),
        ),
        constraints: const BoxConstraints(
          minWidth: 68,
          maxWidth: 68,
        ),
        itemBuilder: (context) => [
          for (final tool in tools)
            PopupMenuItem<int>(
              value: tool.tabIndex,
              enabled: enabled,
              padding: EdgeInsets.zero,
              height: 52,
              child: Center(
                child: Icon(
                  tool.icon,
                  size: 26,
                  color: tool.tabIndex == selectedTool
                      ? const Color(0xff09c47c)
                      : const Color(0xff5f6b6e),
                ),
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
          child: Icon(CupertinoIcons.ellipsis, size: 28, color: color),
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
    final Color color;
    if (onPressed == null) {
      color = const Color(0xff8b9a9e);
    } else if (selected) {
      color = const Color(0xff09c47c);
    } else {
      color = const Color(0xff5f6b6e);
    }

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: IconButton(
          icon: Icon(icon, color: color),
          iconSize: 28,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            foregroundColor: color,
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
    return DragToMoveArea(
      child: Container(
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
