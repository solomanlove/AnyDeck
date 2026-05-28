part of 'dashboard_screen.dart';

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context) {
    return _DeviceOverviewPanel(device: device);
  }
}

/// 展示当前设备身份和 adb 状态的顶部单行 Header，同时包含 scrcpy 投屏控制。

class _DeviceOverviewPanel extends ConsumerWidget {
  const _DeviceOverviewPanel({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = device.isOnline
        ? ref.watch(
            deviceOverviewProvider(device.id).select(
              (value) => value.whenData<DeviceOverview?>((data) => data),
            ),
          )
        : ref.watch(cachedDeviceOverviewProvider(device.id));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: overview.when(
          loading: () => _PanelMessage(
            icon: Icons.phone_android,
            title: context.l10n.t('overviewTitle'),
            subtitle: device.isOnline
                ? context.l10n.t('scanningDevices')
                : context.l10n.t('loadingCachedOverview'),
          ),
          error: (error, stackTrace) => _PanelMessage(
            icon: Icons.error_outline,
            title: context.l10n.t('overviewTitle'),
            subtitle: error.toString(),
          ),
          data: (data) => data == null
              ? _PanelMessage(
                  icon: Icons.info_outline,
                  title: context.l10n.t('overviewTitle'),
                  subtitle: context.l10n.t('noCachedOverview'),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          context.l10n.t('overviewTitle'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Row(
                          children: [
                            const SizedBox(width: 12),
                            _OverviewShortcutActions(device: device),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: context.l10n.t('refresh'),
                              icon: const Icon(Icons.refresh),
                              onPressed: () => device.isOnline
                                  ? ref.invalidate(
                                      deviceOverviewProvider(device.id),
                                    )
                                  : ref.invalidate(
                                      cachedDeviceOverviewProvider(device.id),
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _OverviewGrid(items: _buildOverviewItems(context, data)),
                  ],
                ),
        ),
      ),
    );
  }

  /// 将概览字段映射为图标、标签和值组件。
  List<_OverviewItemData> _buildOverviewItems(
    BuildContext context,
    DeviceOverview overview,
  ) {
    return [
      _OverviewItemData(
        icon: Icons.phone_android,
        label: context.l10n.t('deviceName'),
        value: overview.name,
      ),
      _OverviewItemData(
        icon: Icons.info,
        label: context.l10n.t('brand'),
        value: overview.brand,
      ),
      _OverviewItemData(
        icon: Icons.layers_outlined,
        label: context.l10n.t('model'),
        value: overview.model,
      ),
      _OverviewItemData(
        icon: Icons.pin_outlined,
        label: context.l10n.t('serial'),
        value: overview.serial,
      ),
      _OverviewItemData(
        icon: Icons.badge_outlined,
        label: context.l10n.t('androidId'),
        value: overview.androidId,
      ),
      _OverviewItemData(
        icon: Icons.android,
        label: context.l10n.t('androidVersion'),
        value: overview.androidVersion,
      ),
      _OverviewItemData(
        icon: Icons.android,
        label: context.l10n.t('kernelVersion'),
        value: overview.kernelVersion,
      ),
      _OverviewItemData(
        icon: Icons.memory,
        label: context.l10n.t('processor'),
        value: overview.processor,
      ),
      _OverviewItemData(
        icon: Icons.storage,
        label: context.l10n.t('storage'),
        value: overview.storage,
      ),
      _OverviewItemData(
        icon: Icons.developer_board,
        label: context.l10n.t('memory'),
        value: overview.memory,
      ),
      _OverviewItemData(
        icon: Icons.stay_current_portrait,
        label: context.l10n.t('physicalResolution'),
        value: overview.physicalResolution,
      ),
      _OverviewItemData(
        icon: Icons.stay_current_portrait,
        label: context.l10n.t('resolution'),
        value: overview.resolution,
      ),
      _OverviewItemData(
        icon: Icons.blur_on,
        label: context.l10n.t('logicalDensity'),
        value: overview.logicalDensity,
      ),
      _OverviewItemData(
        icon: Icons.speed,
        label: context.l10n.t('refreshRate'),
        value: overview.refreshRate,
      ),
      _OverviewItemData(
        icon: Icons.text_fields,
        label: context.l10n.t('fontScale'),
        value: overview.fontScale,
      ),
      _OverviewItemData(
        icon: Icons.wifi,
        label: context.l10n.t('wifi'),
        value: overview.wifi,
      ),
      _OverviewItemData(
        icon: Icons.public,
        label: context.l10n.t('ipAddress'),
        value: overview.ipAddress,
      ),
      _OverviewItemData(
        icon: Icons.public,
        label: context.l10n.t('macAddress'),
        value: overview.macAddress,
      ),
    ];
  }
}

/// 概览页右上角常用设备功能入口，保持只读信息页也能快速操作设备。
class _OverviewShortcutActions extends ConsumerWidget {
  const _OverviewShortcutActions({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(deviceActionServiceProvider);
    final enabled = device.isOnline;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: const Color(0xff374151),
            disabledForegroundColor: const Color(0xffa9b0bc),
            minimumSize: const Size(36, 36),
            fixedSize: const Size(36, 36),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: context.l10n.t('home'),
              icon: const Icon(Icons.home_outlined),
              onPressed: enabled
                  ? () => _runAdbAction(
                      context,
                      ref,
                      actions.keyEvent(device.id, 3),
                    )
                  : null,
            ),
            IconButton(
              tooltip: context.l10n.t('back'),
              icon: const Icon(Icons.arrow_back),
              onPressed: enabled
                  ? () => _runAdbAction(
                      context,
                      ref,
                      actions.keyEvent(device.id, 4),
                    )
                  : null,
            ),
            IconButton(
              tooltip: context.l10n.t('power'),
              icon: const Icon(Icons.power_settings_new),
              onPressed: enabled
                  ? () => _runAdbAction(
                      context,
                      ref,
                      actions.keyEvent(device.id, 26),
                    )
                  : null,
            ),
            IconButton(
              tooltip: context.l10n.t('notificationBar'),
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: enabled
                  ? () => _runAdbAction(
                      context,
                      ref,
                      actions.openNotificationBar(device.id),
                    )
                  : null,
            ),
            IconButton(
              tooltip: context.l10n.t('focus'),
              icon: const Icon(Icons.center_focus_strong),
              onPressed: enabled
                  ? () => _showAdbResult(
                      context,
                      ref,
                      actions.currentFocus(device.id),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 概览条目的响应式网格。
class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.items});

  final List<_OverviewItemData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final spacing = 12.0;
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: 16,
          children: [
            for (final item in items) SizedBox(width: itemWidth, child: item),
          ],
        );
      },
    );
  }
}

/// 可点击复制的概览值单元。
class _OverviewItemData extends StatelessWidget {
  const _OverviewItemData({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // 只复制值，不复制标签，便于将 ID、型号、IP 等内容粘贴到其他工具。
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (!context.mounted) {
          return;
        }
        _showSnack(
          context,
          context.l10n.t('copiedToClipboard').replaceAll('{label}', label),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final iconWidth = min(18.0, constraints.maxWidth);
                final showLabel = constraints.maxWidth >= 56;

                return Row(
                  children: [
                    SizedBox(
                      width: iconWidth,
                      height: 18,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Icon(icon, size: 18),
                      ),
                    ),
                    if (showLabel) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// 常用一键设备操作，例如 key event、Wi-Fi 和文本输入。
