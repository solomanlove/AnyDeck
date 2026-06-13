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
        // 清除用户主动清空的选择状态，并选中当前点击的设备
        ref.read(userClearedDeviceSelectionProvider.notifier).state = false;
        ref.read(selectedDeviceProvider.notifier).select(device.toAdbDevice);
      },
      child: Container(
        height: 56,
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
            const SizedBox(width: 10),
            _buildIdentifierCell(context, device),
            const SizedBox(width: 10),
            _buildNameCell(context, device),
            const SizedBox(width: 10),
            _buildStatusCell(context, device),
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

  /// 构建设备标识列（展示设备型号序列号、Wi-Fi IP 以及物理连接/无线调试状态图标）
  Widget _buildIdentifierCell(BuildContext context, RegisteredDevice device) {
    final wifiIp = device.wifiIp;
    final hasUsb = _hasUsbConnection(device);
    final hasNetwork = _hasNetworkConnection(device);

    return Expanded(
      flex: 3,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 首行显示设备型号与序列号
                Text(
                  device.connectionMethodDisplay,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                // 2. 次行展示已获取并缓存的局域网 Wi-Fi IP 地址与网段警告图标
                if (wifiIp != null && wifiIp.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        wifiIp,
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
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
                  ),
                ],
              ],
            ),
          ),
          // USB 连接状态处理
          if (hasUsb) ...[
            const SizedBox(width: 4),
            const Icon(Icons.usb, color: Color(0xFF26A69A), size: 16),
            // 如果 USB 已连接，且存在 Wi-Fi IP，且尚未建立网络 ADB 调试，则提供快捷无线连接按钮
            if (wifiIp != null && wifiIp.isNotEmpty && !hasNetwork) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: '通过 WiFi 连接 ADB',
                child: IconButton(
                  icon: const Icon(CupertinoIcons.link, color: Color(0xFF26A69A), size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 16,
                  onPressed: () => _runAdbAction(
                    context,
                    ref,
                    ref
                        .read(deviceRegistryProvider.notifier)
                        .connectWireless(device.id, wifiIp),
                  ),
                ),
              ),
            ],
          ],
          // 无线/网络连接状态处理
          if (hasNetwork) ...[
            const SizedBox(width: 4),
            const Icon(CupertinoIcons.wifi, color: Color(0xFF26A69A), size: 16),
          ],
        ],
      ),
    );
  }

  /// 构建设备自定义名称（别名）标签列
  Widget _buildNameCell(BuildContext context, RegisteredDevice device) {
    return Expanded(
      flex: 3,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFC8E6C9), width: 1),
              ),
              child: Text(
                device.displayName,
                style: const TextStyle(
                  color: Color(0xFF2E7D32),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 重命名图标按钮，点击弹出重命名对话框
          IconButton(
            icon: const Icon(CupertinoIcons.pencil, size: 14),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            splashRadius: 16,
            onPressed: () => _showRenameDialog(context, device),
          ),
        ],
      ),
    );
  }

  /// 构建设备状态信息展示列（如已在线、未授权等）
  Widget _buildStatusCell(BuildContext context, RegisteredDevice device) {
    return Expanded(
      flex: 2,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getStatusBgColor(device.status),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _getStatusText(context, device.status),
            style: TextStyle(
              color: _getStatusTextColor(device.status),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  /// 构建操作按钮单元格（断开无线调试、连接无线调试以及物理记录的删除）
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
      child: Row(
        children: [
          // 1. 如果已有处于激活在线状态的无线网络调试连接，则显示红色“断开”按钮
          if (hasActiveWifi) ...[
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
            const SizedBox(width: 8),
          ]
          // 2. 若当前无激活无线连接但有已知的 Wi-Fi IP，则显示绿色“连接”按钮
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
            const SizedBox(width: 8),
          ],
          // 3. 删除或清理不活跃的历史离线设备按钮
          IconButton(
            icon: const Icon(CupertinoIcons.trash, color: Colors.redAccent),
            tooltip: context.l10n.t('delete'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              ref.read(deviceRegistryProvider.notifier).removeDevice(device.id);
            },
          ),
        ],
      ),
    );
  }

  /// 检查设备是否拥有活跃的 USB 连接
  bool _hasUsbConnection(RegisteredDevice device) {
    if (device.connections.isEmpty) {
      return !device.isNetwork;
    }
    return device.connections.any(
      (connection) =>
          !(connection.contains(':') ||
              connection.contains('.') ||
              connection == '127.0.0.1'),
    );
  }

  /// 检查设备是否拥有网络 IP/TCP 连接
  bool _hasNetworkConnection(RegisteredDevice device) {
    if (device.connections.isEmpty) {
      return device.isNetwork;
    }
    return device.connections.any(
      (connection) =>
          connection.contains(':') ||
          connection.contains('.') ||
          connection == '127.0.0.1',
    );
  }
}
