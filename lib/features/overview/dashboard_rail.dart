part of '../dashboard_screen.dart';

typedef _PrimaryRail = PrimaryRail;

class PrimaryRail extends ConsumerWidget {
  const PrimaryRail({
    super.key,
    required this.selectedDevice,
    this.isAirplayReceiverRunning = false,
  });

  final DiscoveredDevice? selectedDevice;
  final bool isAirplayReceiverRunning;

  static double get _topSpacing => DesktopChromePolicy.current.sidebarTopInset;
  static const double _fullLogoToolGap = 10;
  static const double _compactLogoToolGap = 6;
  static const double _bottomSpacing = 18;

  int _visibleToolCount({
    required double railHeight,
    required int toolCount,
    required bool isNarrow,
    required bool hasOverflow,
  }) {
    // 顶部工具项使用更紧凑的间距，底部设置等保留原有高度以防变动
    final double toolSlotHeight = isNarrow ? 54.0 : 48.0;
    final double bottomButtonsSlotHeight = (isNarrow ? 60.0 : 52.0) * 4;
    final double logoSize = isNarrow ? 50.0 : 38.0;
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

    // 判断当前 Tab 是否可用；三个全局管理页始终可用
    bool isToolEnabled(int tabIndex) {
      if (tabIndex == -1 || tabIndex == -2 || tabIndex == -3 || tabIndex == -4 || tabIndex == -5) {
        return true;
      }
      if (selectedDevice == null) {
        return false;
      }
      if (selectedDevice!.isIos) {
        if (!selectedDevice!.isOnline) return tabIndex == 0;
        return const {0, 1, 2, 3, 4, 6, 7, 9}.contains(tabIndex);
      }
      // 鸿蒙 NEXT（纯血鸿蒙）支持：
      // 主页(0)、控制(1)、应用(2)、进程(6)、文件(3)、日志(4)、终端(5)、网页调试(7)、截图(9)、网络(11，HTTP 代理面板对鸿蒙隐藏)
      if (selectedDevice!.isHarmony) {
        if (!selectedDevice!.isOnline) {
          return tabIndex == 0;
        }
        return tabIndex == 0 ||
            tabIndex == 1 ||
            tabIndex == 2 ||
            tabIndex == 3 ||
            tabIndex == 4 ||
            tabIndex == 5 ||
            tabIndex == 6 ||
            tabIndex == 7 ||
            tabIndex == 9 ||
            tabIndex == 10 ||
            tabIndex == 11;
      }
      if (selectedDevice!.isOnline) {
        return true;
      }
      return tabIndex == 0 || tabIndex == 1 || tabIndex == 2 || tabIndex == 15;
    }

    // 响应式判断：窗口宽度小于1000为窄屏，仅显示Icon；大于等于1000为宽屏，显示Icon+文字
    final bool isNarrow = MediaQuery.of(context).size.width < 1000;
    final double railWidth = isNarrow ? 76.0 : 180.0;

    final hasSelectedDevice = selectedDevice != null &&
        selectedTool != -1 &&
        selectedTool != -2 &&
        selectedTool != -3 &&
        selectedTool != -4 &&
        selectedTool != -5;
    final isIos = hasSelectedDevice && selectedDevice!.isIos;
    final isHarmony = hasSelectedDevice && selectedDevice!.isHarmony;

    final List<_RailToolItem> tools;
    if (!hasSelectedDevice) {
      // 1. 设备管理模式（默认未选择手机）：显示设备管理与模拟器同级 Tab，收起设备专属工具
      tools = [
        _RailToolItem(
          tabIndex: -1,
          icon: Icons.devices,
          label: context.l10n.t('devices'),
        ),
        _RailToolItem(
          tabIndex: -2,
          icon: CupertinoIcons.device_desktop,
          label: context.l10n.t('emulators'),
        ),
        _RailToolItem(
          tabIndex: -3,
          icon: Icons.cast_connected_rounded,
          label: context.l10n.t('receiverCenter'),
        ),
        _RailToolItem(
          tabIndex: -4,
          icon: Icons.share_rounded,
          label: context.l10n.t('harmonyShareTitle'),
        ),
        _RailToolItem(
          tabIndex: -5,
          icon: Icons.layers_outlined,
          label: context.l10n.t('systemVersions'),
        ),
      ];
    } else if (isIos) {
      // 2. iOS 设备专属 Tab 列表
      tools = [
        _RailToolItem(
          tabIndex: 0,
          icon: AppNavigationIcons.overview,
          label: context.l10n.t('overview'),
        ),
        _RailToolItem(
          tabIndex: 1,
          icon: AppNavigationIcons.control,
          label: context.l10n.t('control'),
        ),
        _RailToolItem(
          tabIndex: 2,
          icon: AppNavigationIcons.apps,
          label: context.l10n.t('apps'),
        ),
        _RailToolItem(
          tabIndex: 6,
          icon: AppNavigationIcons.processes,
          label: context.l10n.t('processes'),
        ),
        _RailToolItem(
          tabIndex: 3,
          icon: AppNavigationIcons.files,
          label: context.l10n.t('files'),
        ),
        _RailToolItem(
          tabIndex: 4,
          icon: AppNavigationIcons.logs,
          label: context.l10n.t('logcat'),
        ),
        _RailToolItem(
          tabIndex: 7,
          icon: AppNavigationIcons.web,
          label: context.l10n.t('webpages'),
        ),
        _RailToolItem(
          tabIndex: 9,
          icon: AppNavigationIcons.capture,
          label: context.l10n.t('screenshot'),
        ),
      ];
    } else if (isHarmony) {
      // 3. 鸿蒙设备专属 Tab 列表（支持主页、控制、应用、进程、文件、日志、终端、网页调试、截图、网络端口转发）
      tools = [
        _RailToolItem(
          tabIndex: 0,
          icon: AppNavigationIcons.overview,
          label: context.l10n.t('overview'),
        ),
        _RailToolItem(
          tabIndex: 1,
          icon: AppNavigationIcons.control,
          label: context.l10n.t('control'),
        ),
        _RailToolItem(
          tabIndex: 2,
          icon: AppNavigationIcons.apps,
          label: context.l10n.t('apps'),
        ),
        _RailToolItem(
          tabIndex: 6,
          icon: AppNavigationIcons.processes,
          label: context.l10n.t('processes'),
        ),
        _RailToolItem(
          tabIndex: 3,
          icon: AppNavigationIcons.files,
          label: context.l10n.t('files'),
        ),
        _RailToolItem(
          tabIndex: 4,
          icon: AppNavigationIcons.logs,
          label: context.l10n.t('logcat'),
        ),
        _RailToolItem(
          tabIndex: 5,
          icon: AppNavigationIcons.terminal,
          label: context.l10n.t('terminal'),
        ),
        _RailToolItem(
          tabIndex: 7,
          icon: AppNavigationIcons.web,
          label: context.l10n.t('webpages'),
        ),
        _RailToolItem(
          tabIndex: 9,
          icon: AppNavigationIcons.capture,
          label: context.l10n.t('screenshotRecord'),
        ),
        _RailToolItem(
          tabIndex: 10,
          icon: AppNavigationIcons.performance,
          label: context.l10n.t('performance'),
        ),
        _RailToolItem(
          tabIndex: 11,
          icon: AppNavigationIcons.network,
          label: context.l10n.t('network'),
        ),
      ];
    } else {
      // 4. 安卓设备专属 Tab 列表（全部工具）
      tools = [
        _RailToolItem(
          tabIndex: 0,
          icon: AppNavigationIcons.overview,
          label: context.l10n.t('overview'),
        ),
        _RailToolItem(
          tabIndex: 1,
          icon: AppNavigationIcons.control,
          label: context.l10n.t('control'),
        ),
        _RailToolItem(
          tabIndex: 2,
          icon: AppNavigationIcons.apps,
          label: context.l10n.t('apps'),
        ),
        _RailToolItem(
          tabIndex: 6,
          icon: AppNavigationIcons.processes,
          label: context.l10n.t('processes'),
        ),
        _RailToolItem(
          tabIndex: 3,
          icon: AppNavigationIcons.files,
          label: context.l10n.t('files'),
        ),
        _RailToolItem(
          tabIndex: 4,
          icon: AppNavigationIcons.logs,
          label: context.l10n.t('logcat'),
        ),
        _RailToolItem(
          tabIndex: 5,
          icon: AppNavigationIcons.terminal,
          label: context.l10n.t('terminal'),
        ),
        _RailToolItem(
          tabIndex: 7,
          icon: AppNavigationIcons.web,
          label: context.l10n.t('webpages'),
        ),
        _RailToolItem(
          tabIndex: 9,
          icon: AppNavigationIcons.capture,
          label: context.l10n.t('screenshotRecord'),
        ),
        _RailToolItem(
          tabIndex: 10,
          icon: AppNavigationIcons.performance,
          label: context.l10n.t('performance'),
        ),
        _RailToolItem(
          tabIndex: 11,
          icon: AppNavigationIcons.network,
          label: context.l10n.t('network'),
        ),
        _RailToolItem(
          tabIndex: 15,
          icon: CupertinoIcons.chat_bubble_2,
          label: context.l10n.t('messages'),
        ),
      ];
    }

    void handleTap(int tabIndex) {
      if (tabIndex == -1) {
        context.goNamed(AppRouteNames.devices);
        return;
      }
      if (tabIndex == -2) {
        context.goNamed(AppRouteNames.emulators);
        return;
      }
      if (tabIndex == -3) {
        context.goNamed(AppRouteNames.receivers);
        return;
      }
      if (tabIndex == -4) {
        context.goNamed(AppRouteNames.harmonyShare);
        return;
      }
      if (tabIndex == -5) {
        context.goNamed(AppRouteNames.systemVersions);
        return;
      }
      final device = selectedDevice;
      if (device != null) {
        context.goNamed(
          AppRouteNames.deviceTool,
          pathParameters: {
            'deviceId': device.id,
            'tool': toolSlugForTabIndex(tabIndex),
          },
        );
      }
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: railWidth,
      decoration: BoxDecoration(
        color: DesktopChromePolicy.current.usesMacChrome
            ? (isDark ? Colors.black.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.20))
            : theme.colorScheme.surfaceContainerLow,
      ),
      child: ClipRect(
        child: BackdropFilter(
          enabled: DesktopChromePolicy.current.usesMacChrome,
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
              if (visibleToolCount >= tools.length) {
                visibleToolCount = tools.length - 1;
              }
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
                            context.goNamed(AppRouteNames.devices);
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: _RailIdentity(
                              selectedDevice: (selectedTool == -1 ||
                                      selectedTool == -2 ||
                                      selectedTool == -3 ||
                                      selectedTool == -4 ||
                                      selectedTool == -5)
                                      ? null
                                      : selectedDevice,
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
                  if (tool.tabIndex == -3)
                    ListenableBuilder(
                      listenable: DlnaRendererService.instance,
                      builder: (context, _) {
                        final isRunning = isAirplayReceiverRunning ||
                            DlnaRendererService.instance.isRunning;
                        return _RailButton(
                          icon: tool.icon,
                          selected: selectedTool == tool.tabIndex,
                          isHighlighted: isRunning,
                          statusColor:
                              isRunning ? theme.appColors.success : null,
                          tooltip: tool.label,
                          isNarrow: renderNarrow,
                          verticalPadding: renderNarrow ? 3.0 : 2.0,
                          onPressed: () => handleTap(tool.tabIndex),
                        );
                      },
                    )
                  else
                    _RailButton(
                      icon: tool.icon,
                      selected: selectedTool == tool.tabIndex,
                      tooltip: tool.label,
                      isNarrow: renderNarrow,
                      verticalPadding: renderNarrow ? 3.0 : 2.0,
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
                    verticalPadding: renderNarrow ? 3.0 : 2.0,
                  ),
                const Spacer(),
                _DashboardRailFooter(isNarrow: renderNarrow),
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
