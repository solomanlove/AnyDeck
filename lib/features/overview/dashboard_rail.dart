part of '../dashboard_screen.dart';

class _PrimaryRail extends ConsumerWidget {
  const _PrimaryRail({required this.selectedDevice});

  final AdbDevice? selectedDevice;

  static double get _topSpacing => Platform.isMacOS ? 36.0 : 14.0;
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
    final double bottomButtonsSlotHeight = (isNarrow ? 60.0 : 52.0) * 3;
    final double logoSize = isNarrow ? 50.0 : 36.0;
    final double logoToolGap = isNarrow
        ? (hasOverflow ? _compactLogoToolGap : _fullLogoToolGap)
        : 12.0;

    final availableHeight =
        railHeight -
        _topSpacing -
        logoSize -
        logoToolGap -
        bottomButtonsSlotHeight -
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

    // 判断当前 Tab 是否可用；设备管理(-1)始终可用
    bool isToolEnabled(int tabIndex) {
      if (tabIndex == -1) {
        return true;
      }
      if (selectedDevice == null) {
        return false;
      }
      if (selectedDevice!.isIos) {
        if (!selectedDevice!.isOnline) return tabIndex == 0;
        return const {0, 1, 2, 3, 4, 6, 9}.contains(tabIndex);
      }
      // 鸿蒙 NEXT（纯血鸿蒙）支持：
      // 主页(0)、控制(1)、文件(3)、截图(9)
      if (selectedDevice!.isHarmony) {
        if (!selectedDevice!.isOnline) {
          return tabIndex == 0;
        }
        return tabIndex == 0 || tabIndex == 1 || tabIndex == 3 || tabIndex == 9;
      }
      if (selectedDevice!.isOnline) {
        return true;
      }
      return tabIndex == 0 || tabIndex == 1 || tabIndex == 2;
    }

    // 响应式判断：窗口宽度小于1000为窄屏，仅显示Icon；大于等于1000为宽屏，显示Icon+文字
    final bool isNarrow = MediaQuery.of(context).size.width < 1000;
    final double railWidth = isNarrow ? 76.0 : 180.0;

    final hasSelectedDevice = selectedDevice != null && selectedTool != -1;
    final isIos = hasSelectedDevice && selectedDevice!.isIos;
    final isHarmony = hasSelectedDevice && selectedDevice!.isHarmony;

    final List<_RailToolItem> tools;
    if (!hasSelectedDevice) {
      // 1. 设备管理模式（默认未选择手机）：仅显示设备管理 Tab，去掉其他特定手机下的 Tab
      tools = [
        _RailToolItem(
          tabIndex: -1,
          icon: Icons.devices,
          label: context.l10n.t('devices'),
        ),
      ];
    } else if (isIos) {
      // 2. iOS 设备专属 Tab 列表
      tools = [
        _RailToolItem(
          tabIndex: -1,
          icon: Icons.devices,
          label: context.l10n.t('devices'),
        ),
        _RailToolItem(
          tabIndex: 0,
          icon: CupertinoIcons.device_phone_portrait,
          label: context.l10n.t('overview'),
        ),
        _RailToolItem(
          tabIndex: 1,
          icon: CupertinoIcons.hand_draw,
          label: context.l10n.t('control'),
        ),
        _RailToolItem(
          tabIndex: 2,
          icon: CupertinoIcons.square_grid_2x2,
          label: context.l10n.t('apps'),
        ),
        _RailToolItem(
          tabIndex: 6,
          icon: CupertinoIcons.list_bullet,
          label: context.l10n.t('processes'),
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
          tabIndex: 9,
          icon: CupertinoIcons.camera,
          label: context.l10n.t('screenshot'),
        ),
      ];
    } else if (isHarmony) {
      // 3. 鸿蒙设备专属 Tab 列表（支持主页、控制、文件、截图）
      tools = [
        _RailToolItem(
          tabIndex: -1,
          icon: Icons.devices,
          label: context.l10n.t('devices'),
        ),
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
          tabIndex: 3,
          icon: CupertinoIcons.folder,
          label: context.l10n.t('files'),
        ),
        _RailToolItem(
          tabIndex: 9,
          icon: CupertinoIcons.camera,
          label: context.l10n.t('screenshot'),
        ),
      ];
    } else {
      // 4. 安卓设备专属 Tab 列表（全部工具）
      tools = [
        _RailToolItem(
          tabIndex: -1,
          icon: Icons.devices,
          label: context.l10n.t('devices'),
        ),
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
          tabIndex: 6,
          icon: CupertinoIcons.list_bullet,
          label: context.l10n.t('processes'),
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
    }

    void handleTap(int tabIndex) {
      if (tabIndex == -1) {
        // 切换到设备管理 Tab，清空当前设备选择
        ref.read(userClearedDeviceSelectionProvider.notifier).state = true;
        ref.read(selectedDeviceProvider.notifier).clear();
        ref.read(selectedToolTabProvider.notifier).select(-1);
        return;
      }
      var device = selectedDevice;
      if (device != null) {
        ref.read(selectedToolTabProvider.notifier).select(tabIndex);
      }
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isMcpRunning =
        ref.watch(mcpServerProvider.select((s) => s.isRunning));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: railWidth,
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.20),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool renderNarrow = constraints.maxWidth < 130;
            int visibleToolCount = _visibleToolCount(
              railHeight: constraints.maxHeight,
              toolCount: tools.length,
              isNarrow: renderNarrow,
              hasOverflow: false,
            );
            if (visibleToolCount < tools.length) {
              visibleToolCount = _visibleToolCount(
                railHeight: constraints.maxHeight,
                toolCount: tools.length,
                isNarrow: renderNarrow,
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
                            // 点击顶部身份区清空选中手机，并跳转至设备管理页面
                            ref
                                .read(userClearedDeviceSelectionProvider.notifier)
                                .state = true;
                            ref.read(selectedDeviceProvider.notifier).clear();
                            ref
                                .read(selectedToolTabProvider.notifier)
                                .select(-1);
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: _RailIdentity(
                              selectedDevice:
                                  (selectedTool == -1) ? null : selectedDevice,
                              registeredDevices: registeredDevices,
                              isNarrow: renderNarrow,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: renderNarrow
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
                    selected: selectedTool == tool.tabIndex,
                    tooltip: tool.label,
                    isNarrow: renderNarrow,
                    onPressed: isToolEnabled(tool.tabIndex)
                        ? () => handleTap(tool.tabIndex)
                        : null,
                  ),
                if (hasOverflowTools)
                  _RailMoreButton(
                    tools: overflowTools,
                    hasSelectedDevice: hasSelectedDevice,
                    selectedTool: selectedTool,
                    isToolEnabled: isToolEnabled,
                    onSelected: handleTap,
                    isNarrow: renderNarrow,
                  ),
                const Spacer(),
                _RailButton(
                  icon: CupertinoIcons.compass,
                  tooltip: context.l10n.t('wanAndroid'),
                  isNarrow: renderNarrow,
                  selected: selectedTool == 13,
                  onPressed: () {
                    ref.read(selectedToolTabProvider.notifier).select(13);
                  },
                ),
                _RailButton(
                  icon: CupertinoIcons.sparkles,
                  tooltip: context.l10n.t('aiMcp'),
                  isNarrow: renderNarrow,
                  selected: selectedTool == 14,
                  isHighlighted: isMcpRunning,
                  onPressed: () {
                    ref.read(selectedToolTabProvider.notifier).select(14);
                  },
                ),
                _RailButton(
                  icon: CupertinoIcons.settings,
                  tooltip: context.l10n.t('settings'),
                  isNarrow: renderNarrow,
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
    required this.isToolEnabled,
    required this.onSelected,
    required this.isNarrow,
  });

  final List<_RailToolItem> tools;
  final bool hasSelectedDevice;
  final int selectedTool;
  final bool Function(int) isToolEnabled;
  final ValueChanged<int> onSelected;
  final bool isNarrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final selected =
        hasSelectedDevice && tools.any((tool) => tool.tabIndex == selectedTool);

    // Ellipsis button is enabled only if at least one tool in the overflow is enabled
    final anyEnabled = tools.any((tool) => isToolEnabled(tool.tabIndex));

    final defaultColor = isDark ? const Color(0xffeceff1) : const Color(0xff455a64);
    final disabledColor = isDark ? const Color(0xff546e7a) : const Color(0xff8b9a9e);
    final color = !anyEnabled
        ? disabledColor
        : (selected ? const Color(0xff09c47c) : defaultColor);

    final activeBgColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.35);

    final popupBgColor = isDark ? const Color(0xff1e222b) : const Color(0xfff5f6f8);
    final popupBorderColor = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xffeceef1);

    if (isNarrow) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: PopupMenuButton<int>(
            tooltip: context.l10n.t('moreTools'),
            onSelected: anyEnabled ? onSelected : null,
            enabled: anyEnabled,
            offset: const Offset(66, 0),
            color: popupBgColor,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: popupBorderColor, width: 1),
            ),
            constraints: const BoxConstraints(minWidth: 68, maxWidth: 68),
            itemBuilder: (context) => [
              for (final tool in tools)
                PopupMenuItem<int>(
                  value: tool.tabIndex,
                  enabled: isToolEnabled(tool.tabIndex),
                  padding: EdgeInsets.zero,
                  height: 52,
                  child: Center(
                    child: Icon(
                      tool.icon,
                      size: 26,
                      color: tool.tabIndex == selectedTool
                          ? const Color(0xff09c47c)
                          : (isToolEnabled(tool.tabIndex) ? defaultColor : disabledColor),
                    ),
                  ),
                ),
            ],
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected
                    ? activeBgColor
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
          onSelected: anyEnabled ? onSelected : null,
          enabled: anyEnabled,
          offset: const Offset(164, 0),
          color: popupBgColor,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: popupBorderColor, width: 1),
          ),
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 200),
          itemBuilder: (context) => [
            for (final tool in tools)
              PopupMenuItem<int>(
                value: tool.tabIndex,
                enabled: isToolEnabled(tool.tabIndex),
                height: 40,
                child: Row(
                  children: [
                    Icon(
                      tool.icon,
                      size: 20,
                      color: tool.tabIndex == selectedTool
                          ? const Color(0xff09c47c)
                          : (isToolEnabled(tool.tabIndex) ? defaultColor : disabledColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tool.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: tool.tabIndex == selectedTool
                              ? const Color(0xff09c47c)
                              : (isToolEnabled(tool.tabIndex) ? defaultColor : disabledColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: Material(
            color: selected
                ? activeBgColor
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
    this.isHighlighted = false,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool isNarrow;
  final bool selected;
  final bool isHighlighted;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color color;
    if (onPressed == null) {
      color = isDark ? const Color(0xff546e7a) : const Color(0xff8b9a9e);
    } else if (selected || isHighlighted) {
      color = const Color(0xff09c47c);
    } else {
      color = isDark ? const Color(0xffeceff1) : const Color(0xff455a64);
    }

    final activeBgColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.35);

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
                backgroundColor: (selected || isHighlighted)
                    ? activeBgColor
                    : Colors.transparent,
                disabledForegroundColor: isDark ? const Color(0xff546e7a) : const Color(0xff8b9a9e),
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
            color: (selected || isHighlighted)
                ? activeBgColor
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 44,
                padding: const EdgeInsets.only(left: 10),
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
                          fontWeight: (selected || isHighlighted)
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
