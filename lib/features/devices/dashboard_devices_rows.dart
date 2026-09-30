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
            const SizedBox(width: 10),
            _buildIdentifierCell(context, device),
            const SizedBox(width: 10),
            _buildNameCell(context, device),
            const SizedBox(width: 10),
            _buildRemarkCell(context, device),
            const SizedBox(width: 10),
            _buildTagsCell(context, device),
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

  /// 构建设备标识列（展示设备型号序列号、Wi-Fi IP 以及物理连接/无线调试状态图标）
  Widget _buildIdentifierCell(BuildContext context, RegisteredDevice device) {
    final wifiIp = device.wifiIp;

    return Expanded(
      flex: 3,
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
                    children: [
                      Flexible(
                        child: Text(
                          wifiIp,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
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
                if (!device.isIos && !device.isHarmony)
                  DeviceWirelessStatusLabel(device: device),
              ],
            ),
          ),
          // 标识列只显示通道状态，所有连接操作统一放在右侧操作列。
          DeviceConnectionIndicators(device: device),
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

  /// 构建设备备注（用途）列
  Widget _buildRemarkCell(BuildContext context, RegisteredDevice device) {
    final hasRemark = device.remark != null && device.remark!.isNotEmpty;
    return Expanded(
      flex: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _showRemarkDialog(context, device),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  hasRemark ? device.remark! : '-',
                  style: TextStyle(
                    fontSize: 12,
                    color: hasRemark ? Theme.of(context).colorScheme.onSurface : Colors.grey,
                    fontWeight: hasRemark ? FontWeight.w500 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(CupertinoIcons.pencil, size: 13, color: Colors.grey.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建设备标签标识列
  Widget _buildTagsCell(BuildContext context, RegisteredDevice device) {
    final hasTags = device.tags.isNotEmpty;
    final primary = Theme.of(context).colorScheme.primary;

    return Expanded(
      flex: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _showTagsDialog(context, device),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!hasTags) ...[
                const Text('-', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 4),
              ] else ...[
                Flexible(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: device.tags.map((tag) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: primary.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w600),
                      ),
                    )).toList(),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Icon(CupertinoIcons.pencil, size: 13, color: Colors.grey.withValues(alpha: 0.5)),
            ],
          ),
        ),
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
          // 4. 彻底删除设备并清理关联缓存按钮
          IconButton(
            icon: const Icon(CupertinoIcons.trash, color: Colors.redAccent),
            tooltip: context.l10n.t('delete'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _confirmAndDeleteDevice(context, ref, device),
          ),
        ],
      ),
    );
  }

  /// 确认并删除设备，若设备正通过 USB 物理连接则给予警示提示
  Future<void> _confirmAndDeleteDevice(
    BuildContext context,
    WidgetRef ref,
    RegisteredDevice device,
  ) async {
    final isUsbOnline = device.isOnline && device.hasUsbConnection;
    final title = isUsbOnline
        ? context.l10n.t('usbConnectedDeleteWarningTitle')
        : context.l10n.t('confirmDeleteDeviceTitle');
    final message = isUsbOnline
        ? context.l10n.t('usbConnectedDeleteWarning')
        : context.l10n
            .t('confirmDeleteDeviceMessage')
            .replaceAll('{name}', device.displayName);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.t('delete')),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref.read(deviceRegistryProvider.notifier).removeDevice(device.id);
      if (context.mounted) {
        _showSnack(context, context.l10n.t('deviceDeletedSuccess'));
      }
    }
  }
}
