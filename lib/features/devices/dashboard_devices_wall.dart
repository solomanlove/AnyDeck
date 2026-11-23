part of '../dashboard_screen.dart';

/// 设备墙仅为可见在线卡片排队截图，不给所有手机开启投屏流。
extension _DeviceWallPanel on _DeviceListPanelState {
  Widget _buildDeviceWall(
    List<RegisteredDevice> devices,
    Map<String, String> names,
    Map<String, AirPlaySessionData> sessions, {
    required bool hasBoundedHeight,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final windowWidth = MediaQuery.sizeOf(context).width;
      final gap = windowWidth <= 490 ? 4.0 : 12.0;
      final availableWidth = constraints.maxWidth;
      final columns = windowWidth <= 490
          ? 2
          : max(1, ((availableWidth + gap) / (148 + gap)).floor());
      final width = (availableWidth - (columns - 1) * gap) / columns;
      final rows = (devices.length / columns).ceil();
      return ListView.separated(
        key: const Key('deviceWall'),
        padding: const EdgeInsets.only(top: 12),
        scrollCacheExtent: const ScrollCacheExtent.pixels(0),
        shrinkWrap: !hasBoundedHeight,
        physics: hasBoundedHeight ? null : const NeverScrollableScrollPhysics(),
        itemCount: rows,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
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
  ) => DeviceScreenPreview(
    key: ValueKey('device-screen-preview-${device.id}'),
    deviceId: device.id,
    online: device.isOnline,
    builder: (context, preview) => Consumer(
      builder: (context, ref, _) {
        final overview = ref
            .watch(cachedDeviceOverviewProvider(device.id))
            .value;
        final brand = overview?.brand;
        // 纯 AirPlay 卡片仅代表投屏会话，没有可导航的设备工作区。
        final airplayOnly = session != null && device.id.startsWith('airplay-');
        final canRunAction =
            !device.isOnline ||
            DeviceContextAction.mirror.isEnabledFor(
              device,
              hasAirPlaySession: session != null,
            );
        final (actionKey, actionIcon) = switch (device.isOnline) {
          true => ('screenMirror', Icons.ondemand_video_outlined),
          false when device.id.startsWith('emulator-') => (
            'deviceWorkspaceStartEmulator',
            Icons.play_arrow,
          ),
          false => ('deviceWorkspaceReconnect', Icons.link),
        };
        return Builder(
          builder: (cardContext) => DeviceWallCard(
            key: ValueKey('device-wall-${device.id}'),
            name: name,
            tags: device.tags,
            systemVersion: device.androidVersion ?? '-',
            statusLabel: _workspaceStatus(context, device, session),
            statusDescription: _workspaceStatus(
              context,
              device,
              session,
              detailed: true,
            ),
            brand: brand != null && brand.isNotEmpty && brand != '-'
                ? brand
                : device.isIos
                ? 'Apple'
                : device.isHarmony
                ? 'HarmonyOS'
                : 'Android',
            coverTitle: context.l10n.t(
              !device.isOnline
                  ? 'deviceWorkspaceDisconnected'
                  : preview.isLoading
                  ? 'deviceWorkspacePreviewLoading'
                  : preview.hasError
                  ? 'deviceWorkspacePreviewFailed'
                  : 'deviceWorkspaceReady',
            ),
            coverHint: !device.isOnline
                ? ''
                : context.l10n.t(
                    preview.hasError
                        ? 'deviceWorkspacePreviewRetryHint'
                        : 'deviceWorkspacePreviewHint',
                  ),
            actionLabel: context.l10n.t(actionKey),
            actionIcon: actionIcon,
            previewOpensWorkspace: device.isOnline && !airplayOnly,
            online: device.isOnline,
            ipAddress: _workspaceDeviceIp(device, overview),
            screenshot: device.isOnline && !preview.hasError
                ? preview.value ??
                      ref
                          .read(deviceScreenPreviewProvider(device.id).notifier)
                          .cachedBytes
                : null,
            busy: _deviceQuickActionRunning && _contextDeviceId == device.id,
            batchMode: _batchMode,
            selected: device.isChecked,
            selectable: !device.id.startsWith('airplay-'),
            onOpen: canRunAction
                ? () => _openWorkspaceDevice(context, device, session)
                : null,
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
    ),
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

  /// 与列表共用通道短名称；Tooltip 和读屏通过 detailed 保留完整说明。
  String _workspaceStatus(
    BuildContext context,
    RegisteredDevice device,
    AirPlaySessionData? session, {
    bool detailed = false,
  }) {
    final channels = DeviceListPresentation.connections(
      device,
      isAirplayMirroring: session != null,
    );
    if (channels.isEmpty) {
      return context.l10n.t(
        device.isOnline
            ? 'connectionUnknown'
            : DeviceListPresentation.statusKey(device),
      );
    }
    return channels
        .map(
          (channel) => context.l10n.t(
            detailed ? channel.fullLabelKey : channel.shortLabelKey,
          ),
        )
        .join(' · ');
  }

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
