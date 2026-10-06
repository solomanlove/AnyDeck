part of '../dashboard_screen.dart';

/// 按设备平台生成概览详情，避免将 Android 密度等语义套用到 iOS。
extension _OverviewDetails on DeviceOverviewContent {
  List<_OverviewDetailData> _systemNetworkItems(BuildContext context) {
    if (device.isIos) return _iosSystemItems(context, overview);
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
    if (device.isIos) return _iosScreenItems(context, overview);
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
