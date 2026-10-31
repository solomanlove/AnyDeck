part of '../dashboard_screen.dart';

/// 设备表格行渲染，和面板容器分离，便于维护列结构。
extension _DeviceListPanelRows on _DeviceListPanelState {
  /// 构建单个设备行
  Widget _buildDeviceRow(
    BuildContext context,
    RegisteredDevice device,
    bool isSelected,
    bool isCompact,
    int index, {
    AirPlaySessionData? airplaySession,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color? rowColor = isSelected
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
        : airplaySession != null
        ? const Color(0xFF34C759).withValues(alpha: isDark ? 0.10 : 0.06)
        : index % 2 == 0
        ? null
        : Theme.of(
            context,
          ).colorScheme.surfaceContainerLowest.withValues(alpha: 0.5);

    void handleRowOpen() {
      // 纯 AirPlay 接入的虚拟设备未注册 go-ios UDID，点击直接打开其 AirPlay 投屏窗口
      if (device.id.startsWith('airplay-') && airplaySession != null) {
        openAirPlayMirrorWindow(
          airplaySession,
          deviceId: device.id,
          deviceName: device.displayName,
        );
        return;
      }
      // 已注册设备行直接进入概览，批量选择继续由 Checkbox 承担。
      context.goNamed(
        AppRouteNames.deviceTool,
        pathParameters: {'deviceId': device.id, 'tool': 'overview'},
      );
    }

    return InkWell(
      onTap: handleRowOpen,
      onDoubleTap: handleRowOpen,
      child: Container(
        // 长状态文案、放大字体和操作换行时允许行高增长。
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: rowColor,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            if (!isCompact) ...[
              SizedBox(
                width: 45,
                child: Checkbox(
                  value: device.isChecked,
                  onChanged: device.id.startsWith('airplay-')
                      ? null
                      : (_) {
                          // 切换该设备的勾选状态
                          ref
                              .read(deviceRegistryProvider.notifier)
                              .toggleCheck(device.id);
                        },
                ),
              ),
              const SizedBox(width: 10),
            ],
            _buildIdentifierCell(context, device, airplaySession),
            const SizedBox(width: 10),
            _buildRemarkCell(context, device),
            const SizedBox(width: 10),
            _buildAndroidVersionCell(context, device),
            const SizedBox(width: 10),
            _buildActionsCell(context, device, airplaySession),
            if (!isCompact) ...[
              const SizedBox(width: 10),
              const SizedBox(
                width: 40,
                child: Icon(CupertinoIcons.chevron_right, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建设备标识与自定义名称列（展示设备 Logo、自定义名称、Wi-Fi IP、分辨率以及通道状态图标）
  Widget _buildIdentifierCell(
    BuildContext context,
    RegisteredDevice device,
    AirPlaySessionData? airplaySession,
  ) {
    return Expanded(
      flex: 4,
      child: Row(
        children: [
          // 设备品牌/系统 Logo，结合角标和灰阶直观标识在线或离线状态
          DeviceStatusAvatar(device: device),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 首行展示设备名称，若处于 AirPlay 投屏中展示 LIVE 徽章，随后展示自定义标签
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        device.displayName,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (airplaySession != null) ...[
                      const SizedBox(width: 6),
                      const DeviceAirPlayLiveBadge(),
                    ],
                    if (device.tags.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      ...device.tags.map((tag) => Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )),
                    ],
                  ],
                ),
                // 2. 次行展示已获取的局域网 Wi-Fi IP 地址 / 投屏分辨率及警告图标
                _buildIdentifierSubtitle(device, airplaySession),
                if (!device.isIos && !device.isHarmony)
                  DeviceWirelessStatusLabel(device: device),
              ],
            ),
          ),
          // 标识列只显示通道状态，所有连接操作统一放在右侧操作列；离线时由组件内部隐藏
          DeviceConnectionIndicators(
            device: device,
            isAirplayMirroring: airplaySession != null,
          ),
        ],
      ),
    );
  }

  /// Android 设备行复用概览的 WLAN IP；ADB 连接端点仍由设备模型负责命令路由。
  Widget _buildIdentifierSubtitle(
    RegisteredDevice device,
    AirPlaySessionData? airplaySession,
  ) {
    return Consumer(
      builder: (context, ref, _) {
        final overviewIp = device.isIos || device.isHarmony
            ? null
            : ref.watch(
                deviceOverviewProvider(device.id).select(
                  (value) => value.value?.ipAddress,
                ),
              );
        final wifiIp = overviewIp == null
            ? device.wifiIp
            : (overviewIp == '-' || overviewIp.isEmpty ? null : overviewIp);
        final hasIp = wifiIp != null && wifiIp.isNotEmpty;
        final resolutionText =
            (airplaySession != null &&
                airplaySession.width > 0 &&
                airplaySession.height > 0)
            ? '${airplaySession.width} × ${airplaySession.height}'
            : null;
        final String? subtitleText = switch ((hasIp, resolutionText != null)) {
          (true, true) => '$wifiIp · $resolutionText',
          (true, false) => wifiIp,
          (false, true) => resolutionText,
          (false, false) => null,
        };
        if (subtitleText == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  subtitleText,
                  style: TextStyle(
                    fontSize: 11,
                    color: airplaySession != null && !hasIp
                        ? const Color(0xFF34C759)
                        : Colors.grey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasIp) DeviceSubnetWarning(wifiIp: wifiIp),
            ],
          ),
        );
      },
    );
  }

  /// 构建设备备注（用途）列
  Widget _buildRemarkCell(BuildContext context, RegisteredDevice device) {
    final hasRemark = device.remark != null && device.remark!.isNotEmpty;
    return Expanded(
      flex: 3,
      child: Text(
        hasRemark ? device.remark! : '-',
        style: TextStyle(
          fontSize: 12,
          color: hasRemark ? Theme.of(context).colorScheme.onSurface : Colors.grey,
          fontWeight: hasRemark ? FontWeight.w500 : FontWeight.normal,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 构建设备系统版本列，展示 Android release 与 API 级别。
  Widget _buildAndroidVersionCell(
    BuildContext context,
    RegisteredDevice device,
  ) {
    final version = device.androidVersion;
    return Expanded(
      flex: 2,
      child: Text(
        version == null || version.isEmpty ? '-' : version,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 构建操作按钮单元格（投屏、断开无线调试、连接无线调试以及物理记录的删除）
  Widget _buildActionsCell(
    BuildContext context,
    RegisteredDevice device,
    AirPlaySessionData? airplaySession,
  ) {
    // 找出设备在线的无线连接 ID (如 192.168.1.100:5555)
    final activeWifiId = device.isOnline
        ? device.connections.firstWhere(
            (conn) =>
                conn.contains(':') ||
                conn.contains('.') ||
                conn == '127.0.0.1',
            orElse: () => '',
          )
        : '';

    final hasActiveWifi = activeWifiId.isNotEmpty;
    final wifiIp = device.wifiIp;
    // iOS 列表常规入口只支持 USB 投屏；AirPlay 活跃时无论是否连接 USB 均展示方案 C 纯图标按钮组
    final canMirror = device.isOnline &&
        (!device.isIos || device.hasUsbConnection);

    return Expanded(
      flex: 2,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 0. 若当前设备正通过 AirPlay 投屏中，展示方案 C 纯图标按钮组（打开投屏窗口 + 停止投屏）
          if (airplaySession != null) ...[
            DeviceAirPlayActionButtons(
              device: device,
              session: airplaySession,
            ),
          ]
          // 1. 若设备在线且非 AirPlay 投屏状态，显示常规独立投屏按钮
          else if (canMirror) ...[
            IconButton(
              icon: const Icon(
                CupertinoIcons.tv,
                color: Color(0xFF26A69A),
              ),
              tooltip: context.l10n.t('screenMirror'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => openStandaloneMirrorWindow(
                context,
                ref,
                device.toDiscoveredDevice,
              ),
            ),
          ],
          // 2. 如果已有处于激活在线状态的无线网络调试连接，则显示红色“断开”按钮
          if (!device.isIos && !device.isHarmony) ...[
            DeviceWirelessControls(device: device),
          ] else if (hasActiveWifi) ...[
            IconButton(
              icon: const Icon(
                CupertinoIcons.bolt_slash,
                color: Colors.red,
              ),
              tooltip: context.l10n.t('disconnect'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _runAdbAction(
                context,
                ref,
                ref
                    .read(deviceRegistryProvider.notifier)
                    .disconnectDevice(activeWifiId),
              ),
            ),
          ]
          // 3. 若当前无激活无线连接但有已知的 Wi-Fi IP，则显示绿色“连接”按钮
          else if (wifiIp != null && wifiIp.isNotEmpty) ...[
            IconButton(
              icon: const Icon(
                CupertinoIcons.link,
                color: Colors.green,
              ),
              tooltip: context.l10n.t('connect'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _runAdbAction(
                context,
                ref,
                device.isOnline
                    ? ref
                        .read(deviceRegistryProvider.notifier)
                        .connectWireless(device.id, wifiIp)
                    : ref
                        .read(deviceRegistryProvider.notifier)
                        .connectDevice('$wifiIp:5555'),
              ),
            ),
          ],
          // 4. 编辑设备信息按钮（修改设备名称、标签标识、备注，并在弹窗内展示详情及提供删除功能）
          if (!device.id.startsWith('airplay-'))
            IconButton(
              icon: const Icon(
                CupertinoIcons.pencil,
                color: Color(0xFF1976D2),
              ),
              tooltip: context.l10n.t('editDeviceInfo'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _showEditDeviceInfoDialog(context, device),
            ),
        ],
      ),
    );
  }
}
