part of '../dashboard_screen.dart';

class _PrimaryRail extends ConsumerWidget {
  const _PrimaryRail({required this.selectedDevice});

  final AdbDevice? selectedDevice;

  static double get _topSpacing => Platform.isMacOS ? 36.0 : 14.0;
  static const double _logoSize = 50;
  static const double _fullLogoToolGap = 10;
  static const double _compactLogoToolGap = 6;
  static const double _bottomSpacing = 18;

  int _visibleToolCount({
    required double railHeight,
    required int toolCount,
    required bool isNarrow,
    required bool hasOverflow,
  }) {
    final double toolSlotHeight = isNarrow ? 60.0 : 52.0;
    final double settingsSlotHeight = isNarrow ? 60.0 : 52.0;
    final double logoSize = isNarrow ? 50.0 : 36.0;
    final double logoToolGap = isNarrow
        ? (hasOverflow ? _compactLogoToolGap : _fullLogoToolGap)
        : 12.0;

    final availableHeight =
        railHeight -
        _topSpacing -
        logoSize -
        logoToolGap -
        settingsSlotHeight -
        _bottomSpacing;

    if (availableHeight <= 0) return 0;
    final slots = availableHeight ~/ toolSlotHeight;
    if (slots >= toolCount) {
      return toolCount;
    }
    if (slots <= 1) {
      return 0;
    }
    return min(toolCount, slots - 1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTool = ref.watch(selectedToolTabProvider);
    final registeredDevices = ref.watch(deviceRegistryProvider);
    final hasOnlineDevice = registeredDevices.any((d) => d.isOnline);
    final canInteract = selectedDevice != null || hasOnlineDevice;

    // 响应式判断：窗口宽度小于1000为窄屏，仅显示Icon；大于等于1000为宽屏，显示Icon+文字
    final bool isNarrow = MediaQuery.of(context).size.width < 1000;
    final double railWidth = isNarrow ? 76.0 : 180.0;

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
        // 查找第一个在线的设备
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: railWidth,
      color: const Color(0xffe1e4e5),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            int visibleToolCount = _visibleToolCount(
              railHeight: constraints.maxHeight,
              toolCount: tools.length,
              isNarrow: isNarrow,
              hasOverflow: false,
            );
            if (visibleToolCount < tools.length) {
              visibleToolCount = _visibleToolCount(
                railHeight: constraints.maxHeight,
                toolCount: tools.length,
                isNarrow: isNarrow,
                hasOverflow: true,
              );
            }
            final visibleTools = tools.take(visibleToolCount).toList();
            final overflowTools = tools.skip(visibleToolCount).toList();
            final hasOverflowTools = overflowTools.isNotEmpty;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                    .read(
                                      userClearedDeviceSelectionProvider
                                          .notifier,
                                    )
                                    .state =
                                true;
                            ref.read(selectedDeviceProvider.notifier).clear();
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: isNarrow
                                ? SizedBox(
                                    width: _logoSize,
                                    height: _logoSize,
                                    child: const Image(
                                      image: AssetImage(
                                        'assets/brand/app_logo.png',
                                      ),
                                    ),
                                  )
                                : Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(
                                          width: 36,
                                          height: 36,
                                          child: Image(
                                            image: AssetImage(
                                              'assets/brand/app_logo.png',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            context.l10n.t('appTitle'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xff202124),
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                        SizedBox(
                          height: isNarrow
                              ? (hasOverflowTools
                                    ? _compactLogoToolGap
                                    : _fullLogoToolGap)
                              : 12.0,
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
                    isNarrow: isNarrow,
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
                    isNarrow: isNarrow,
                  ),
                const Spacer(),
                _RailButton(
                  icon: CupertinoIcons.settings,
                  tooltip: context.l10n.t('settings'),
                  isNarrow: isNarrow,
                  selected: selectedTool == 12,
                  onPressed: () {
                    ref.read(selectedToolTabProvider.notifier).select(12);
                  },
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
    required this.isNarrow,
  });

  final List<_RailToolItem> tools;
  final bool hasSelectedDevice;
  final int selectedTool;
  final bool enabled;
  final ValueChanged<int> onSelected;
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    final selected =
        hasSelectedDevice && tools.any((tool) => tool.tabIndex == selectedTool);
    final color = selected ? const Color(0xff09c47c) : const Color(0xff5f6b6e);

    if (isNarrow) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
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
            constraints: const BoxConstraints(minWidth: 68, maxWidth: 68),
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
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: PopupMenuButton<int>(
          tooltip: context.l10n.t('moreTools'),
          onSelected: enabled ? onSelected : null,
          offset: const Offset(164, 0),
          color: const Color(0xfff5f6f8),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xffeceef1), width: 1),
          ),
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 200),
          itemBuilder: (context) => [
            for (final tool in tools)
              PopupMenuItem<int>(
                value: tool.tabIndex,
                enabled: enabled,
                height: 40,
                child: Row(
                  children: [
                    Icon(
                      tool.icon,
                      size: 20,
                      color: tool.tabIndex == selectedTool
                          ? const Color(0xff09c47c)
                          : const Color(0xff5f6b6e),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tool.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: tool.tabIndex == selectedTool
                              ? const Color(0xff09c47c)
                              : const Color(0xff5f6b6e),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: Material(
            color: selected
                ? Colors.white.withValues(alpha: 0.56)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(CupertinoIcons.ellipsis, size: 24, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.t('moreTools'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.isNarrow,
    this.selected = false,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool isNarrow;
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

    if (isNarrow) {
      return Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(
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
        ),
      );
    } else {
      return Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          child: Material(
            color: selected
                ? Colors.white.withValues(alpha: 0.56)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(icon, size: 24, color: color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tooltip,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: color,
                        ),
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
}
