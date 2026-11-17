part of '../dashboard_screen.dart';

/// 设备墙只创建可见卡片，静态封面按需取图，不给所有手机开启投屏流。
extension _DeviceWallPanel on _DeviceListPanelState {
  Widget _buildDeviceWall(
    List<RegisteredDevice> devices,
    Map<String, String> names,
    Map<String, AirPlaySessionData> sessions, {
    required bool hasBoundedHeight,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final windowWidth = MediaQuery.sizeOf(context).width;
      final gap = windowWidth <= 490
          ? 4.0
          : windowWidth <= 650
          ? 8.0
          : 14.0;
      final columns = windowWidth <= 490
          ? 2
          : max(1, ((constraints.maxWidth + gap) / (166 + gap)).floor());
      final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
      final rows = (devices.length / columns).ceil();
      return ListView.separated(
        key: const Key('deviceWall'),
        padding: const EdgeInsets.only(top: 4, bottom: 20),
        shrinkWrap: !hasBoundedHeight,
        physics: hasBoundedHeight ? null : const NeverScrollableScrollPhysics(),
        itemCount: rows,
        separatorBuilder: (_, _) => SizedBox(
          height: windowWidth <= 490
              ? 15
              : windowWidth <= 650
              ? 14
              : 17,
        ),
        itemBuilder: (context, row) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var column = 0; column < columns; column++) ...[
              if (column > 0) SizedBox(width: gap),
              SizedBox(
                width: width,
                child: row * columns + column >= devices.length
                    ? null
                    : _buildWallCard(
                        context,
                        devices[row * columns + column],
                        names[devices[row * columns + column].id]!,
                        sessions[devices[row * columns + column].id],
                      ),
              ),
            ],
          ],
        ),
      );
    },
  );

  Widget _buildWallCard(
    BuildContext context,
    RegisteredDevice device,
    String name,
    AirPlaySessionData? session,
  ) => Consumer(
    builder: (context, ref, _) {
      final overview = ref.watch(cachedDeviceOverviewProvider(device.id)).value;
      final preview = ref.watch(deviceScreenPreviewProvider(device.id));
      final brand = overview?.brand;
      return Builder(
        builder: (cardContext) => DeviceWallCard(
          key: ValueKey('device-wall-${device.id}'),
          name: name,
          systemVersion: device.androidVersion ?? '-',
          statusLabel: _workspaceStatus(context, device, session),
          brand: brand != null && brand.isNotEmpty && brand != '-'
              ? brand
              : device.isIos
              ? 'Apple'
              : device.isHarmony
              ? 'HarmonyOS'
              : 'Android',
          coverTitle: context.l10n.t(
            device.isOnline
                ? 'deviceWorkspaceReady'
                : 'deviceWorkspaceDisconnected',
          ),
          coverHint: context.l10n.t(
            device.isOnline
                ? 'deviceWorkspacePreviewHint'
                : 'deviceWorkspaceConnectHint',
          ),
          actionLabel: context.l10n.t(
            device.isOnline
                ? 'screenMirror'
                : device.id.startsWith('emulator-')
                ? 'deviceWorkspaceStartEmulator'
                : 'deviceWorkspaceReconnect',
          ),
          actionIcon: device.isOnline
              ? Icons.ondemand_video_outlined
              : device.id.startsWith('emulator-')
              ? Icons.play_arrow
              : Icons.link,
          online: device.isOnline,
          ipAddress: _workspaceDeviceIp(device, overview),
          screenshot: device.isOnline ? preview.value : null,
          busy:
              preview.isLoading ||
              (_deviceQuickActionRunning && _contextDeviceId == device.id),
          batchMode: _batchMode,
          selected: device.isChecked,
          selectable: !device.id.startsWith('airplay-'),
          onOpen: () => _openWorkspaceDevice(context, device, session),
          onInfo: () => _openDeviceInfo(context, device, session),
          onMore: () => _openWorkspaceMenu(cardContext, device, session),
          onSelected: (_) => _toggleDeviceSelection(device),
          onSecondaryTapDown: _batchMode
              ? null
              : (details) => _showDeviceContextMenu(
                  context,
                  device,
                  details.globalPosition,
                  airplaySession: session,
                ),
        ),
      );
    },
  );

  /// 两种视图使用同一份缓存地址，不因切换布局改变设备身份信息。
  String? _workspaceDeviceIp(
    RegisteredDevice device,
    DeviceOverview? overview,
  ) {
    final candidate = overview?.ipAddress;
    return candidate != null && candidate.isNotEmpty && candidate != '-'
        ? candidate
        : device.wifiIp;
  }

  String _workspaceStatus(
    BuildContext context,
    RegisteredDevice device,
    AirPlaySessionData? session,
  ) => context.l10n.t(
    session != null
        ? 'deviceWorkspaceAirplay'
        : !device.isOnline
        ? DeviceListPresentation.statusKey(device)
        : device.hasUsbConnection
        ? 'deviceWorkspaceUsbConnected'
        : 'deviceWorkspaceWifiConnected',
  );

  void _toggleDeviceSelection(RegisteredDevice device) {
    if (!device.id.startsWith('airplay-')) {
      ref.read(deviceRegistryProvider.notifier).toggleCheck(device.id);
    }
  }

  void _openDeviceInfo(
    BuildContext context,
    RegisteredDevice device,
    AirPlaySessionData? session,
  ) {
    if (_batchMode) {
      _toggleDeviceSelection(device);
      return;
    }
    if (device.id.startsWith('airplay-') && session != null) {
      openAirPlayMirrorWindow(
        session,
        deviceId: device.id,
        deviceName: device.displayName,
      );
      return;
    }
    context.goNamed(
      AppRouteNames.deviceTool,
      pathParameters: {'deviceId': device.id, 'tool': 'overview'},
    );
  }

  /// 更多菜单和右键共享能力检查；菜单锚定对应设备而非当前选中设备。
  void _openWorkspaceMenu(
    BuildContext context,
    RegisteredDevice device,
    AirPlaySessionData? session,
  ) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    _showDeviceContextMenu(
      context,
      device,
      box.localToGlobal(Offset(box.size.width, box.size.height)),
      airplaySession: session,
    );
  }

  Future<void> _openWorkspaceDevice(
    BuildContext context,
    RegisteredDevice device,
    AirPlaySessionData? session,
  ) async {
    if (_batchMode) {
      _toggleDeviceSelection(device);
      return;
    }
    if (_deviceQuickActionRunning) {
      return;
    }
    _selectContextDevice(device.id);
    _setDeviceQuickActionRunning(true);
    try {
      if (!device.isOnline && device.id.startsWith('emulator-')) {
        context.goNamed(AppRouteNames.emulators);
      } else if (session != null) {
        await openAirPlayMirrorWindow(
          session,
          deviceId: device.id,
          deviceName: device.displayName,
        );
      } else if (device.isOnline &&
          (!device.isIos || device.hasUsbConnection)) {
        await openStandaloneMirrorWindow(
          context,
          ref,
          device.toDiscoveredDevice,
        );
      } else if (device.isHarmony) {
        // HDC 复用自己的无线连接入口，不能将鸿蒙地址交给 ADB。
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(dialogContext.l10n.t('harmonyWirelessTitle')),
            content: const SizedBox(
              width: 560,
              height: 500,
              child: HarmonyWirelessConnectionView(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(dialogContext.l10n.t('close')),
              ),
            ],
          ),
        );
      } else if (device.isIos) {
        // iOS 通过 USB 解锁、信任电脑与 go-ios 发现，提供已有授权引导。
        await PlatformEnvironmentGuideDialog.show(
          context,
          initialPlatform: TargetPlatformType.ios,
        );
      } else if (!device.isShared) {
        await _runAdbAction(
          context,
          ref,
          ref
              .read(deviceRegistryProvider.notifier)
              .connectPreferredAdbWireless(device),
        );
      } else {
        await _showConnectDeviceDialog(context, ref);
      }
    } catch (error) {
      if (context.mounted) {
        _showSnack(
          context,
          '${context.l10n.t('error')}: $error',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        _setDeviceQuickActionRunning(false);
      }
    }
  }
}
