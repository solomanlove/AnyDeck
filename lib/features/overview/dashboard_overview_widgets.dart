part of '../dashboard_screen.dart';

const _overviewAccent = Color(0xff09c47c);

/// 按窗口宽度组织设备摘要、重点指标和详细参数。
class DeviceOverviewContent extends StatelessWidget {
  const DeviceOverviewContent({
    super.key,
    required this.device,
    required this.overview,
    required this.onRefresh,
  });

  final AdbDevice device;
  final DeviceOverview overview;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return _ToolTabScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OverviewHeader(onRefresh: onRefresh),
          const SizedBox(height: 12),
          _OverviewIdentityCard(device: device, overview: overview),
          const SizedBox(height: 12),
          _OverviewVersionCard(device: device, overview: overview),
          const SizedBox(height: 12),
          _OverviewResponsivePair(
            first: _OverviewCapacityCard(
              label: context.l10n.t('memory'),
              icon: CupertinoIcons.square_grid_2x2,
              value: '${overview.memoryUsed} / ${overview.memory}',
              targetTab: 6,
            ),
            second: _OverviewCapacityCard(
              label: context.l10n.t('storageSpace'),
              icon: CupertinoIcons.archivebox,
              value: overview.storage,
              targetTab: 3,
            ),
          ),
          const SizedBox(height: 12),
          _OverviewResponsivePair(
            first: _OverviewDetailCard(
              title: context.l10n.t('systemNetwork'),
              icon: CupertinoIcons.wifi,
              items: _systemNetworkItems(context),
            ),
            second: _OverviewDetailCard(
              title: context.l10n.t('screenDisplay'),
              icon: CupertinoIcons.tv,
              items: _screenItems(context),
            ),
          ),
        ],
      ),
    );
  }

  List<_OverviewDetailData> _systemNetworkItems(BuildContext context) {
    return [
      _OverviewDetailData(
        label: context.l10n.t('processor'),
        value: overview.processor,
      ),
      _OverviewDetailData(
        label: context.l10n.t('kernelVersion'),
        value: overview.kernelVersion,
      ),
      _OverviewDetailData(label: context.l10n.t('wifi'), value: overview.wifi),
      _OverviewDetailData(
        label: context.l10n.t('ipAddress'),
        value: overview.ipAddress,
      ),
      _OverviewDetailData(
        label: context.l10n.t('macAddress'),
        value: overview.macAddress,
      ),
    ];
  }

  List<_OverviewDetailData> _screenItems(BuildContext context) {
    return [
      _OverviewDetailData(
        label: context.l10n.t('physicalResolution'),
        value: overview.physicalResolution,
      ),
      _OverviewDetailData(
        label: context.l10n.t('resolution'),
        value: overview.resolution,
      ),
      _OverviewDetailData(
        label: context.l10n.t('logicalDensity'),
        value: overview.logicalDensity,
        tooltip: ScreenDensityHelper.getDensityMappingTooltip(
          context.l10n.t('densityMapping'),
        ),
      ),
      _OverviewDetailData(
        label: context.l10n.t('refreshRate'),
        value: overview.refreshRate,
      ),
      _OverviewDetailData(
        label: context.l10n.t('fontScale'),
        value: overview.fontScale,
      ),
    ];
  }
}

/// 宽屏使用双列，窄屏自动堆叠，避免长设备参数被压缩。
class _OverviewResponsivePair extends StatelessWidget {
  const _OverviewResponsivePair({
    required this.first,
    required this.second,
  });

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 12), second],
          );
        }
        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
        return row;
      },
    );
  }
}

class _OverviewHeader extends StatelessWidget {
  const _OverviewHeader({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            context.l10n.t('overviewTitle'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton.outlined(
          tooltip: context.l10n.t('refresh'),
          icon: const Icon(CupertinoIcons.refresh),
          onPressed: onRefresh,
        ),
      ],
    );
  }
}

/// 顶部只展示一次设备身份信息，避免与详情卡重复。
class _OverviewIdentityCard extends StatelessWidget {
  const _OverviewIdentityCard({required this.device, required this.overview});

  final AdbDevice device;
  final DeviceOverview overview;

  @override
  Widget build(BuildContext context) {
    final items = [
      _OverviewIdentityData(
        icon: CupertinoIcons.device_phone_portrait,
        value: overview.name,
        secondary: overview.brand,
      ),
      _OverviewIdentityData(
        icon: CupertinoIcons.number_square,
        label: context.l10n.t('serial'),
        value: overview.serial,
      ),
      if (!device.isHarmony && overview.brand != 'Apple')
        _OverviewIdentityData(
          icon: CupertinoIcons.person_crop_square,
          label: context.l10n.t('androidId'),
          value: overview.androidId,
        ),
    ];

    return _OverviewSurface(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final status = _OverviewStatusChip(isOnline: device.isOnline);
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                status,
                const SizedBox(height: 14),
                for (var index = 0; index < items.length; index++) ...[
                  if (index > 0) const Divider(height: 17),
                  _OverviewIdentityItem(data: items[index]),
                ],
              ],
            );
          }
          return Row(
            children: [
              status,
              const SizedBox(width: 20),
              for (final item in items) ...[
                const SizedBox(height: 48, child: VerticalDivider(width: 25)),
                Expanded(child: _OverviewIdentityItem(data: item)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _OverviewStatusChip extends StatelessWidget {
  const _OverviewStatusChip({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final color = isOnline
        ? _overviewAccent
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              context.l10n.t(isOnline ? 'deviceOnline' : 'deviceOffline'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewIdentityItem extends StatelessWidget {
  const _OverviewIdentityItem({required this.data});

  final _OverviewIdentityData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () =>
          _copyOverviewValue(context, data.label ?? data.value, data.value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            Icon(data.icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (data.label != null || data.secondary != null)
                    Text(
                      data.label ?? data.secondary!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 将 Android 版本拆为主版本与 API badge，其他系统保持原始版本文本。
class _OverviewVersionCard extends StatelessWidget {
  const _OverviewVersionCard({required this.device, required this.overview});

  final AdbDevice device;
  final DeviceOverview overview;

  @override
  Widget build(BuildContext context) {
    final display = _VersionDisplay.parse(overview.androidVersion);
    final isApple = overview.brand == 'Apple';
    final label = device.isHarmony
        ? context.l10n.t('harmonyOsVersion')
        : isApple
        ? context.l10n.t('iosVersion')
        : context.l10n.t('androidVersion');
    final customOs = !device.isHarmony && !isApple
        ? (overview.customOs.isEmpty || overview.customOs == '-'
              ? context.l10n.t('customOsUnknown')
              : overview.customOs)
        : null;
    final isAndroid = !device.isHarmony && !isApple;

    return _OverviewHeroCard(
      icon: CupertinoIcons.device_phone_portrait,
      label: label,
      trailing: isAndroid
          ? AndroidVersionInfoIcon(currentVersion: overview.androidVersion)
          : null,
      onTap: () => _copyOverviewValue(context, label, overview.androidVersion),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final valueStyle = Theme.of(context).textTheme.displaySmall?.copyWith(
            fontSize: constraints.maxWidth < 320 ? 30 : 40,
            fontWeight: FontWeight.w800,
            height: 1.05,
          );
          return Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 32,
            runSpacing: 12,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(display.version, style: valueStyle),
                  if (display.api != null) _OverviewBadge(text: display.api!),
                ],
              ),
              if (customOs != null)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customOs,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.t('customOs'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
