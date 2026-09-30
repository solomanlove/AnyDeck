part of '../dashboard_screen.dart';

/// 设备表格行渲染，和面板容器分离，便于维护列结构。
extension _DeviceListPanelRows on _DeviceListPanelState {
  /// 构建单个设备行
  Widget _buildDeviceRow(
    BuildContext context,
    RegisteredDevice device,
    bool isSelected,
    bool isCompact,
    int index,
  ) {
    final Color? rowColor = isSelected
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
        : index % 2 == 0
        ? null
        : Theme.of(
            context,
          ).colorScheme.surfaceContainerLowest.withValues(alpha: 0.5);

    return InkWell(
      onTap: () {
        // 设备行直接进入概览，批量选择继续由 Checkbox 承担。
        context.goNamed(
          AppRouteNames.deviceTool,
          pathParameters: {'deviceId': device.id, 'tool': 'overview'},
        );
      },
      onDoubleTap: () {
        context.goNamed(
          AppRouteNames.deviceTool,
          pathParameters: {'deviceId': device.id, 'tool': 'overview'},
        );
      },
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
                  onChanged: (_) {
                    // 切换该设备的勾选状态
                    ref
                        .read(deviceRegistryProvider.notifier)
                        .toggleCheck(device.id);
                  },
                ),
              ),
              const SizedBox(width: 10),
            ],
            _buildIdentifierCell(context, device),
            const SizedBox(width: 10),
            _buildRemarkCell(context, device),
            const SizedBox(width: 10),
            _buildAndroidVersionCell(context, device),
            const SizedBox(width: 10),
            _buildActionsCell(context, device),
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

  /// 构建设备标识与自定义名称列（展示设备 Logo、自定义名称、硬件型号、Wi-Fi IP 以及通道状态图标）
  Widget _buildIdentifierCell(BuildContext context, RegisteredDevice device) {
    final wifiIp = device.wifiIp;
    final hasCustomName = device.customName != null && device.customName!.isNotEmpty;

    // 次行辅助信息：有自定义名称时展示硬件型号，结合 IP 展示
    final String? subtitleText;
    if (hasCustomName) {
      final modelStr = device.connectionMethodDisplay;
      if (wifiIp != null && wifiIp.isNotEmpty) {
        subtitleText = '$modelStr · $wifiIp';
      } else {
        subtitleText = modelStr;
      }
    } else if (wifiIp != null && wifiIp.isNotEmpty) {
      subtitleText = wifiIp;
    } else {
      subtitleText = null;
    }

    return Expanded(
      flex: 4,
      child: Row(
        children: [
          // 设备品牌/系统 Logo，结合角标和灰阶直观标识在线或离线状态
          DeviceStatusAvatar(device: device),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 首行展示设备名称，若包含标签标识则紧随其后展示（无标签时不展示）
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
                // 2. 次行展示硬件型号代号与已获取的局域网 Wi-Fi IP 地址及警告图标
                if (subtitleText != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          subtitleText,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (wifiIp != null && wifiIp.isNotEmpty) ...[
                        FutureBuilder<bool>(
                          future: _subnetFutures.putIfAbsent(
                            wifiIp,
                            () => NetworkLanMatcher.isSameSubnet(wifiIp),
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data == false) {
                              return const Padding(
                                padding: EdgeInsets.only(left: 4.0),
                                child: Tooltip(
                                  message: '手机与电脑可能不在同一局域网网段',
                                  child: Icon(
                                    CupertinoIcons.exclamationmark_circle_fill,
                                    color: Colors.amber,
                                    size: 14,
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ],
                  ),
                ],
                if (!device.isIos && !device.isHarmony)
                  DeviceWirelessStatusLabel(device: device),
              ],
            ),
          ),
          // 标识列只显示通道状态，所有连接操作统一放在右侧操作列；离线时由组件内部隐藏
          DeviceConnectionIndicators(device: device),
        ],
      ),
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
  Widget _buildActionsCell(BuildContext context, RegisteredDevice device) {
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

    return Expanded(
      flex: 2,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 1. 若设备在线，显示独立投屏按钮
          if (device.isOnline) ...[
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
                device.toAdbDevice,
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
