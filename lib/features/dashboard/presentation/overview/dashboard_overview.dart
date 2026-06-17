part of '../dashboard_screen.dart';

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

    return overview.when(
      loading: () => _PanelMessage(
        icon: CupertinoIcons.arrow_2_circlepath,
        title: context.l10n.t('overviewTitle'),
        subtitle: device.isOnline
            ? context.l10n.t('scanningDevices')
            : context.l10n.t('loadingCachedOverview'),
        animateIcon: true,
      ),
      error: (error, stackTrace) => _PanelMessage(
        icon: CupertinoIcons.exclamationmark_circle,
        title: context.l10n.t('overviewTitle'),
        subtitle: error.toString(),
      ),
      data: (data) => data == null
          ? _PanelMessage(
              icon: CupertinoIcons.info_circle,
              title: context.l10n.t('overviewTitle'),
              subtitle: context.l10n.t('noCachedOverview'),
            )
          : _ToolTabScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OverviewHeader(
                    device: device,
                    onRefresh: () => device.isOnline
                        ? ref.invalidate(deviceOverviewProvider(device.id))
                        : ref.invalidate(cachedDeviceOverviewProvider(device.id)),
                  ),
                  const SizedBox(height: 8),
                  _buildCategorySection(
                    context,
                    title: context.l10n.t('basicInfo'),
                    icon: CupertinoIcons.device_phone_portrait,
                    items: _buildBasicInfoItems(context, data),
                  ),
                  const SizedBox(height: 8),
                  _buildCategorySection(
                    context,
                    title: context.l10n.t('systemHardware'),
                    icon: CupertinoIcons.settings,
                    items: _buildSystemHardwareItems(context, data),
                  ),
                  const SizedBox(height: 8),
                  _buildCategorySection(
                    context,
                    title: context.l10n.t('networkConnectivity'),
                    icon: CupertinoIcons.wifi,
                    items: _buildNetworkConnectivityItems(context, data),
                  ),
                  const SizedBox(height: 8),
                  _buildCategorySection(
                    context,
                    title: context.l10n.t('screenDisplay'),
                    icon: CupertinoIcons.tv,
                    items: _buildScreenDisplayItems(context, data),
                  ),
                ],
              ),
            ),
    );
  }

  /// 构建分类卡片 Section。
  Widget _buildCategorySection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<_OverviewItemData> items,
  }) {
    final theme = Theme.of(context);
    return _GlassSectionCard(
      title: title,
      icon: icon,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: const Color(0xff09c47c),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _OverviewGrid(items: items),
      ],
    );
  }

  /// 获取基本信息概览列表。
  List<_OverviewItemData> _buildBasicInfoItems(
    BuildContext context,
    DeviceOverview overview,
  ) {
    return [
      _OverviewItemData(
        icon: CupertinoIcons.device_phone_portrait,
        label: context.l10n.t('deviceName'),
        value: overview.name,
      ),
      _OverviewItemData(
        icon: CupertinoIcons.info,
        label: context.l10n.t('brand'),
        value: overview.brand,
      ),
      _OverviewItemData(
        icon: CupertinoIcons.layers,
        label: context.l10n.t('model'),
        value: overview.model,
      ),
      _OverviewItemData(
        icon: CupertinoIcons.number,
        label: context.l10n.t('serial'),
        value: overview.serial,
      ),
      _OverviewItemData(
        icon: CupertinoIcons.person_crop_square,
        label: context.l10n.t('androidId'),
        value: overview.androidId,
      ),
    ];
  }

  /// 获取系统与硬件概览列表。
  List<_OverviewItemData> _buildSystemHardwareItems(
    BuildContext context,
    DeviceOverview overview,
  ) {
    return [
      _OverviewItemData(
        icon: CupertinoIcons.device_phone_portrait,
        label: context.l10n.t('androidVersion'),
        value: overview.androidVersion,
        tooltip: AndroidVersionHelper.getApiMappingTooltip(
          context.l10n.t('androidApiMapping'),
        ),
      ),
      _OverviewItemData(
        icon: CupertinoIcons.device_phone_portrait,
        label: context.l10n.t('kernelVersion'),
        value: overview.kernelVersion,
      ),
      _OverviewItemData(
        icon: CupertinoIcons.settings,
        label: context.l10n.t('processor'),
        value: overview.processor,
      ),
      _OverviewItemData(
        icon: CupertinoIcons.folder,
        label: context.l10n.t('storage'),
        value: overview.storage,
      ),
      _OverviewItemData(
        icon: CupertinoIcons.square_grid_2x2,
        label: context.l10n.t('memory'),
        value: overview.memory,
      ),
    ];
  }

  /// 获取屏幕与显示概览列表。
  List<_OverviewItemData> _buildScreenDisplayItems(
    BuildContext context,
    DeviceOverview overview,
  ) {
    return [
      _OverviewItemData(
        icon: CupertinoIcons.device_phone_portrait,
        label: context.l10n.t('physicalResolution'),
        value: overview.physicalResolution,
      ),
      _OverviewItemData(
        icon: CupertinoIcons.device_phone_portrait,
        label: context.l10n.t('resolution'),
        value: overview.resolution,
      ),
      _OverviewItemData(
        icon: CupertinoIcons.circle_grid_3x3,
        label: context.l10n.t('logicalDensity'),
        value: overview.logicalDensity,
        tooltip: ScreenDensityHelper.getDensityMappingTooltip(
          context.l10n.t('densityMapping'),
        ),
      ),
      _OverviewItemData(
        icon: CupertinoIcons.gauge,
        label: context.l10n.t('refreshRate'),
        value: overview.refreshRate,
      ),
      _OverviewItemData(
        icon: CupertinoIcons.textformat,
        label: context.l10n.t('fontScale'),
        value: overview.fontScale,
      ),
    ];
  }

  /// 获取网络与连接概览列表。
  List<_OverviewItemData> _buildNetworkConnectivityItems(
    BuildContext context,
    DeviceOverview overview,
  ) {
    return [
      _OverviewItemData(
        icon: CupertinoIcons.wifi,
        label: context.l10n.t('wifi'),
        value: overview.wifi,
      ),
      _OverviewItemData(
        icon: CupertinoIcons.globe,
        label: context.l10n.t('ipAddress'),
        value: overview.ipAddress,
      ),
      _OverviewItemData(
        icon: CupertinoIcons.globe,
        label: context.l10n.t('macAddress'),
        value: overview.macAddress,
      ),
    ];
  }
}

/// 概览区域标题栏，极窄宽度下改为上下排列，避免快捷按钮挤压标题。
class _OverviewHeader extends StatelessWidget {
  const _OverviewHeader({required this.device, required this.onRefresh});

  final AdbDevice device;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Text(
          context.l10n.t('overviewTitle'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        );
        final actions = IconButton(
          tooltip: context.l10n.t('refresh'),
          icon: const Icon(CupertinoIcons.refresh),
          onPressed: onRefresh,
        );
        return Row(
          children: [
            Expanded(child: title),
            actions,
          ],
        );
      },
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
        final columns = constraints.maxWidth >= 600
            ? 3
            : constraints.maxWidth >= 400
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
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    // 只复制值，不复制标签，便于将 ID、型号、IP 等内容粘贴到其他工具。
    final child = InkWell(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final iconWidth = min(18.0, constraints.maxWidth);
              final showLabel = constraints.maxWidth >= 56;

              final color = Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
              return Row(
                children: [
                  SizedBox(
                    width: iconWidth,
                    height: 18,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Icon(icon, size: 18, color: color),
                    ),
                  ),
                  if (showLabel) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context,).textTheme.titleSmall
                            ?.copyWith(color: color),
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
    );

    if (tooltip != null) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      return Tooltip(
        message: tooltip!,
        preferBelow: false,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.all(8),
        verticalOffset: 24,
        textStyle: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: Colors.white,
          height: 1.4,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.grey[900]!.withAlpha(242)
              : Colors.black.withAlpha(217),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark
                ? Colors.white.withAlpha(31)
                : Colors.white.withAlpha(51),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(64),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: child,
      );
    }

    return child;
  }
}

/// 常用一键设备操作，例如 key event、Wi-Fi 和文本输入。
