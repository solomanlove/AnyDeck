part of '../dashboard_screen.dart';

/// 主窗口内容与全局页面编排，控制台的布局由外层 Shell 独立管理。
extension _DashboardContent on _DashboardScreenState {
  Widget _buildDashboardContent(BuildContext context) {
    final selectedDevice = ref.watch(selectedDeviceProvider);
    final sessions = ref.watch(scrcpySessionsProvider);
    final registeredDevices = ref.watch(deviceRegistryProvider);
    final lastActiveDevice = ref.watch(lastActiveDeviceProvider);
    final settings = ref.watch(appSettingsProvider);
    _scheduleDashboardRouteSync();

    var effectiveSelectedDevice = selectedDevice;
    String appBarTitle = context.l10n.t('appTitle');
    if (selectedDevice != null) {
      final matchedDevice = registeredDevices.firstWhere(
        (d) =>
            d.id == selectedDevice.id ||
            (d.serial != null &&
                d.serial!.isNotEmpty &&
                d.serial == selectedDevice.id) ||
            (selectedDevice.id.length > d.id.length &&
                selectedDevice.id.endsWith(d.id)),
        orElse: () => RegisteredDevice(
          id: selectedDevice.id,
          status: selectedDevice.status,
          model: selectedDevice.model,
          product: selectedDevice.product,
          transportId: selectedDevice.transportId,
          isOnline: selectedDevice.isOnline,
          serial: selectedDevice.id,
        ),
      );
      effectiveSelectedDevice = matchedDevice.toDiscoveredDevice;
      appBarTitle = matchedDevice.displayName;

      if (_hasDeviceSnapshotChanged(selectedDevice, effectiveSelectedDevice)) {
        final syncedDevice = effectiveSelectedDevice;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final current = ref.read(selectedDeviceProvider);
          if (current != null &&
              _hasDeviceSnapshotChanged(current, syncedDevice)) {
            ref.read(selectedDeviceProvider.notifier).select(syncedDevice);
          }
        });
      }
    }

    if (effectiveSelectedDevice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final current = ref.read(lastActiveDeviceProvider);
        if (_hasDeviceSnapshotChanged(effectiveSelectedDevice!, current)) {
          ref.read(lastActiveDeviceProvider.notifier).state =
              effectiveSelectedDevice;
        }

        // iOS 仅开放已接入 go-ios 的工具页。
        if (effectiveSelectedDevice.isIos) {
          final selectedTool = ref.read(selectedToolTabProvider);
          const iosTabs = {0, 1, 2, 3, 4, 6, 7, 9, 12, 13, 14};
          if (selectedTool >= 0 && !iosTabs.contains(selectedTool)) {
            _goToDeviceTool(effectiveSelectedDevice.id, 0);
          }
        } else if (effectiveSelectedDevice.isHarmony) {
          // 鸿蒙设备支持主页(0)、控制(1)、应用(2)、文件(3)、日志(4)、终端(5)、进程(6)、网页调试(7)、截图(9)、性能(10)、网络(11)、设置(12)、玩安卓(13)、AI MCP(14)
          final selectedTool = ref.read(selectedToolTabProvider);
          if (selectedTool >= 0 &&
              selectedTool != 0 &&
              selectedTool != 1 &&
              selectedTool != 2 &&
              selectedTool != 3 &&
              selectedTool != 4 &&
              selectedTool != 5 &&
              selectedTool != 6 &&
              selectedTool != 7 &&
              selectedTool != 9 &&
              selectedTool != 10 &&
              selectedTool != 11 &&
              selectedTool != 12 &&
              selectedTool != 13 &&
              selectedTool != 14) {
            _goToDeviceTool(effectiveSelectedDevice.id, 0);
          }
        } else if (!effectiveSelectedDevice.isOnline) {
          // 当手机离线时，如果当前选择的不是主页(0)、控制(1)、应用(2)、消息(15)、设置(12)、玩安卓(13)或 AI MCP(14) Tab，则自动重定向回主页 Tab
          final selectedTool = ref.read(selectedToolTabProvider);
          if (selectedTool >= 0 &&
              selectedTool != 0 &&
              selectedTool != 1 &&
              selectedTool != 2 &&
              selectedTool != 15 &&
              selectedTool != 12 &&
              selectedTool != 13 &&
              selectedTool != 14) {
            _goToDeviceTool(effectiveSelectedDevice.id, 0);
          }
        }
      });
    }

    final selectedTool = ref.watch(selectedToolTabProvider);
    final workspace = _WorkspacePanel(
      selectedDevice: effectiveSelectedDevice ?? lastActiveDevice,
      sessions: sessions,
    );

    final int stackIndex;
    if (selectedTool == 12) {
      stackIndex = 2;
    } else if (selectedTool == 13) {
      stackIndex = 3;
      _hasVisitedWanAndroid = true;
    } else if (selectedTool == 14) {
      stackIndex = 4;
    } else if (selectedTool == -2) {
      stackIndex = 5;
    } else if (selectedTool == -3) {
      stackIndex = 6;
    } else if (selectedTool == -4) {
      stackIndex = 7;
    } else if (selectedTool == -5) {
      stackIndex = 8;
    } else if (selectedTool == -1 || effectiveSelectedDevice == null) {
      stackIndex = 0;
    } else {
      stackIndex = 1;
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyQ, meta: true):
            _handleQuitShortcut,
        const SingleActivator(LogicalKeyboardKey.keyQ, control: true):
            _handleQuitShortcut,
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () {
          context.goNamed(AppRouteNames.settings);
        },
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () {
          context.goNamed(AppRouteNames.settings);
        },
      },
      child: MainWindowCloseShortcut(
        showWindowKey: settings.showWindowShortcutKey,
        showWindowShortcut: settings.mainWindowBinding,
        onQuit: _handleQuitShortcut,
        child: Scaffold(
          body: _WechatStyleShell(
            title: appBarTitle,
            selectedDevice: effectiveSelectedDevice,
            isAirplayReceiverRunning: _isAirplayReceiverRunning,
            child: IndexedStack(
              index: stackIndex,
              children: [
                const _DashboardHomeContent(),
                workspace,
                const _SettingsTab(),
                if (_hasVisitedWanAndroid)
                  const InAppWebViewWidget(
                    initialUrl: 'https://www.wanandroid.com/',
                    title: '玩Android',
                  )
                else
                  const SizedBox.shrink(),
                const McpDashboardTab(),
                // 复用完整模拟器列表布局，仅访问时加载，避免后台扫描。
                if (selectedTool == -2)
                  const EmulatorListPanel(isFullPage: true)
                else
                  const SizedBox.shrink(),
                if (selectedTool == -3)
                  const ReceiverDashboardTab()
                else
                  const SizedBox.shrink(),
                if (selectedTool == -4)
                  const HarmonyShareDashboardTab()
                else
                  const SizedBox.shrink(),
                if (selectedTool == -5)
                  const SystemVersionsPage()
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
