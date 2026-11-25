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
    required double connectionWidth,
  }) {
    final theme = Theme.of(context);
    final selected = _batchMode && device.isChecked;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _DeviceTableLayout.resolve(
          context,
          constraints.maxWidth,
          _batchMode,
          connectionWidth,
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
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: selected || isSelected
                  ? theme.deviceSelectionBackground
                  : theme.appColors.panelSurface,
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_batchMode)
                      SizedBox(
                        width: 36,
                        child: Checkbox(
                          activeColor: theme.colorScheme.onSurface,
                          checkColor: theme.colorScheme.surface,
                          side: theme.deviceSelectionCheckboxSide,
                          overlayColor: WidgetStatePropertyAll(
                            theme.appColors.hoverSurface,
                          ),
                          value: device.isChecked,
                          onChanged: device.id.startsWith('airplay-')
                              ? null
                              : (_) => _toggleDeviceSelection(device),
                        ),
                      ),
                    Expanded(
                      child: Row(
                        children: [
                          DeviceStatusAvatar(
                            device: device,
                            size: 36,
                            cacheOnly: true,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 3,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    for (final tag in device.tags)
                                      if (tag.trim().isNotEmpty)
                                        DeviceTagBadge(tag: tag),
                                  ],
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
                                    softWrap: true,
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
                        width: _DeviceTableLayout.systemWidth,
                        key: ValueKey('device-system-column-${device.id}'),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            device.androidVersion ?? '-',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                            ),
                            softWrap: true,
                          ),
                        ),
                      ),
                    if (!_batchMode)
                      SizedBox(
                        width: layout.actionsWidth,
                        child: _buildWorkspaceActions(
                          device,
                          airplaySession,
                          compact: layout.phone,
                        ),
                      ),
                  ],
                ),
                // 窄屏状态独占内容宽度，多个通道仍横排，避免挤进设备名称的小列。
                if (layout.statusInline)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: _deviceStatus(
                      context,
                      device,
                      airplaySession,
                      key: ValueKey('device-status-inline-${device.id}'),
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
  }) => DeviceConnectionIndicators(
    key: key,
    device: device,
    isAirplayMirroring: session != null,
    showLabels: true,
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
    RegisteredDevice device,
    AirPlaySessionData? session, {
    bool compact = false,
  }) => Consumer(
    builder: (context, ref, _) {
      final launch = _watchWorkspaceEmulatorLaunch(context, ref, device);
      final (actionKey, actionIcon) = _workspaceActionAppearance(device, launch);
      final onPressed = _deviceQuickActionRunning || launch?.starting == true
          ? null
          : () => _openWorkspaceDevice(context, device, session);
      final label = _workspaceActionLabel(
        context,
        actionKey,
        actionIcon,
        compact,
      );
      final style = _workspaceActionStyle(context, device.isOnline);
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: device.isOnline
                ? FilledButton.tonal(
                    onPressed: onPressed,
                    style: style,
                    child: label,
                  )
                : OutlinedButton(
                    onPressed: onPressed,
                    style: style,
                    child: label,
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
    },
  );

  /// 桌面操作保持单行，空间不足时先隐藏图标；窄屏仍允许标签自然换行。
  Widget _workspaceActionLabel(
    BuildContext context,
    String actionKey,
    IconData actionIcon,
    bool compact,
  ) {
    final label = context.l10n.t(actionKey);
    return Tooltip(
      message: label,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: DefaultTextStyle.of(context).style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final showIcon = !compact && constraints.maxWidth >= painter.width + 21;
          painter.dispose();
          return Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showIcon) ...[
                Icon(actionIcon, size: 16),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: compact ? null : 1,
                  softWrap: compact,
                  overflow: compact ? TextOverflow.clip : TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

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

  /// 版本独立列留出完整常规版本与 API 空间，长版本仍允许自然换行。
  static const systemWidth = 160.0;

  final bool phone;
  final bool systemInline;
  final bool statusInline;
  final double statusWidth;
  final double actionsWidth;

  static _DeviceTableLayout resolve(
    BuildContext context,
    double available,
    bool batchMode,
    double connectionWidth,
  ) {
    final windowWidth = MediaQuery.sizeOf(context).width;
    final phone = windowWidth <= 490;
    final inner = available - 16 - (batchMode ? 36 : 0);
    final statusWidth = connectionWidth;
    var actionsWidth = batchMode
        ? 0.0
        : windowWidth <= 730
        ? 132.0
        : 155.0;
    var systemInline = windowWidth <= 730;
    var statusInline = phone;
    if (!systemInline && inner - actionsWidth - statusWidth - systemWidth < 84) {
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
