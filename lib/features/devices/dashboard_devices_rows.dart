part of '../dashboard_screen.dart';

/// 列表与手机墙共用设备身份、状态和操作，默认不出现多选控件。
extension _DeviceListPanelRows on _DeviceListPanelState {
  Widget _buildDeviceRow(
    BuildContext context,
    RegisteredDevice device,
    bool isSelected,
    bool isCompact,
    int index, {
    AirPlaySessionData? airplaySession,
    required String displayName,
  }) {
    final theme = Theme.of(context);
    final selected = _batchMode && device.isChecked;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _DeviceTableLayout.resolve(
          context,
          constraints.maxWidth,
          _batchMode,
        );
        return InkWell(
          key: ValueKey('device-row-${device.id}'),
          onTap: () => _batchMode
              ? _toggleDeviceSelection(device)
              : _openDeviceInfo(context, device, airplaySession),
          onSecondaryTapDown: _batchMode
              ? null
              : (details) => _showDeviceContextMenu(
                  context,
                  device,
                  details.globalPosition,
                  airplaySession: airplaySession,
                ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: EdgeInsets.symmetric(
              horizontal: layout.phone ? 8 : 11,
              vertical: layout.phone ? 15 : 18,
            ),
            decoration: BoxDecoration(
              color: selected || isSelected
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : theme.appColors.panelSurface,
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                if (_batchMode)
                  SizedBox(
                    width: 36,
                    child: Checkbox(
                      value: device.isChecked,
                      onChanged: device.id.startsWith('airplay-')
                          ? null
                          : (_) => _toggleDeviceSelection(device),
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 36,
                        decoration: BoxDecoration(
                          color: device.isOnline
                              ? theme.colorScheme.primaryContainer.withValues(
                                  alpha: 0.5,
                                )
                              : theme.appColors.subtleSurface,
                          borderRadius: AppThemeSizes.radiusMedium,
                        ),
                        child: Icon(
                          Icons.smartphone_outlined,
                          size: 20,
                          color: device.isOnline
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              displayName,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            _buildIdentifierSubtitle(device, airplaySession),
                            if (layout.systemInline)
                              Text(
                                device.androidVersion ?? '-',
                                key: ValueKey(
                                  'device-system-inline-${device.id}',
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (layout.statusInline)
                              _deviceStatus(
                                context,
                                device,
                                airplaySession,
                                key: ValueKey(
                                  'device-status-inline-${device.id}',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!layout.statusInline)
                  SizedBox(
                    width: layout.statusWidth,
                    key: ValueKey('device-status-column-${device.id}'),
                    child: _deviceStatus(context, device, airplaySession),
                  ),
                if (!layout.systemInline)
                  SizedBox(
                    width: 108,
                    key: ValueKey('device-system-column-${device.id}'),
                    child: Text(
                      device.androidVersion ?? '-',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (!_batchMode)
                  SizedBox(
                    width: layout.actionsWidth,
                    child: _buildWorkspaceActions(
                      context,
                      device,
                      airplaySession,
                      compact: layout.phone,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _deviceStatus(
    BuildContext context,
    RegisteredDevice device,
    AirPlaySessionData? session, {
    Key? key,
  }) => Row(
    key: key,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (device.isOnline) ...[
        Icon(Icons.circle, size: 5, color: Theme.of(context).appColors.success),
        const SizedBox(width: 4),
      ],
      Flexible(
        child: Text(
          _workspaceStatus(context, device, session),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: device.isOnline
                ? Theme.of(context).appColors.success
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );

  /// 读取与设备墙同源的 WLAN IP，不额外发起全量概览探测。
  Widget _buildIdentifierSubtitle(
    RegisteredDevice device,
    AirPlaySessionData? session,
  ) => Consumer(
    builder: (context, ref, _) {
      final overview = ref.watch(cachedDeviceOverviewProvider(device.id));
      final ip = _workspaceDeviceIp(device, overview.value);
      if (ip == null || ip.isEmpty) {
        return const SizedBox.shrink();
      }
      return Row(
        children: [
          Flexible(
            child: Text(
              ip,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (!device.isShared) DeviceSubnetWarning(wifiIp: ip),
        ],
      );
    },
  );

  Widget _buildWorkspaceActions(
    BuildContext context,
    RegisteredDevice device,
    AirPlaySessionData? session, {
    bool compact = false,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Flexible(
        child: device.isOnline
            ? FilledButton.tonal(
                onPressed: _deviceQuickActionRunning
                    ? null
                    : () => _openWorkspaceDevice(context, device, session),
                style: _workspaceActionStyle(context, device.isOnline),
                child: _workspaceActionLabel(context, device, compact),
              )
            : OutlinedButton(
                onPressed: _deviceQuickActionRunning
                    ? null
                    : () => _openWorkspaceDevice(context, device, session),
                style: _workspaceActionStyle(context, device.isOnline),
                child: _workspaceActionLabel(context, device, compact),
              ),
      ),
      const SizedBox(width: 5),
      Builder(
        builder: (buttonContext) => IconButton(
          tooltip: context.l10n.t('deviceWorkspaceMore'),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 28, height: 32),
          padding: EdgeInsets.zero,
          onPressed: () => _openWorkspaceMenu(buttonContext, device, session),
          icon: const Icon(Icons.more_horiz, size: 18),
        ),
      ),
    ],
  );

  /// 窄屏与原型一致隐藏主操作图标，标签可换行以适应英文及放大字号。
  Widget _workspaceActionLabel(
    BuildContext context,
    RegisteredDevice device,
    bool compact,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (!compact) ...[
        Icon(
          device.isOnline
              ? Icons.ondemand_video_outlined
              : device.id.startsWith('emulator-')
              ? Icons.play_arrow
              : Icons.link,
          size: 16,
        ),
        const SizedBox(width: 5),
      ],
      Flexible(
        child: Text(
          context.l10n.t(
            device.isOnline
                ? 'screenMirror'
                : device.id.startsWith('emulator-')
                ? 'deviceWorkspaceStartEmulator'
                : 'deviceWorkspaceReconnect',
          ),
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );

  ButtonStyle _workspaceActionStyle(BuildContext context, bool online) =>
      FilledButton.styleFrom(
        minimumSize: const Size(0, 31),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        textStyle: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontSize: 12),
        backgroundColor: online
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).appColors.panelSurface,
        foregroundColor: online
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        side: BorderSide(
          color: online
              ? Colors.transparent
              : Theme.of(context).colorScheme.outlineVariant,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: AppThemeSizes.radiusMedium,
        ),
        visualDensity: VisualDensity.compact,
      );
}

/// 列表按整窗断点选择列结构，再按实际工作区宽度兜底，防止窄内容横向溢出。
class _DeviceTableLayout {
  const _DeviceTableLayout({
    required this.phone,
    required this.systemInline,
    required this.statusInline,
    required this.statusWidth,
    required this.actionsWidth,
  });

  final bool phone;
  final bool systemInline;
  final bool statusInline;
  final double statusWidth;
  final double actionsWidth;

  static _DeviceTableLayout resolve(
    BuildContext context,
    double available,
    bool batchMode,
  ) {
    final windowWidth = MediaQuery.sizeOf(context).width;
    final phone = windowWidth <= 490;
    final inner = available - (phone ? 16 : 22) - (batchMode ? 36 : 0);
    final statusWidth = windowWidth <= 730 ? 95.0 : 114.0;
    var actionsWidth = batchMode
        ? 0.0
        : windowWidth <= 730
        ? 132.0
        : 155.0;
    var systemInline = windowWidth <= 730;
    var statusInline = phone;
    if (!systemInline && inner - actionsWidth - statusWidth - 108 < 84) {
      systemInline = true;
    }
    if (!statusInline && inner - actionsWidth - statusWidth < 84) {
      statusInline = true;
      systemInline = true;
    }
    if (!batchMode) {
      actionsWidth = min(actionsWidth, max(64, inner - 84));
    }
    return _DeviceTableLayout(
      phone: phone,
      systemInline: systemInline,
      statusInline: statusInline,
      statusWidth: statusWidth,
      actionsWidth: actionsWidth,
    );
  }
}
