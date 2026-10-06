part of '../dashboard_screen.dart';

/// iOS 概览使用独立标签与来源说明，缺失读数不代表零值或关闭状态。
String _iosValue(BuildContext context, String? value) =>
    value == null || value.isEmpty || value == '-'
    ? context.l10n.t('iosValueUnavailable')
    : value;

String _iosMemoryValue(BuildContext context, DeviceOverview overview) =>
    overview.memory == '-'
    ? context.l10n.t('iosValueUnavailable')
    : '${_iosValue(context, overview.memoryUsed)} / ${overview.memory}';

List<_OverviewDetailData> _iosSystemItems(
  BuildContext context,
  DeviceOverview overview,
) {
  final details = overview.iosDetails;
  final spec = IosModelSpec.byProductType[details?.productType];
  final cores = details?.cpuCores;
  return [
    _OverviewDetailData(
      label: context.l10n.t('iosHardwareModel'),
      value: _iosValue(context, details?.hardwareModel),
    ),
    _OverviewDetailData(
      label: context.l10n.t('iosCpuArchitecture'),
      value: _iosValue(context, overview.processor),
    ),
    if (cores != null)
      _OverviewDetailData(
        label: context.l10n.t('iosCpuCores'),
        value: '$cores',
      ),
    if (spec != null)
      _OverviewDetailData(
        label: context.l10n.t('iosChipSpec'),
        value: spec.chip,
      ),
    _OverviewDetailData(
      label: context.l10n.t('iosBuildVersion'),
      value: _iosValue(context, details?.buildVersion),
    ),
    _OverviewDetailData(
      label: context.l10n.t('kernelVersion'),
      value: _iosValue(context, overview.kernelVersion),
    ),
    _OverviewDetailData(
      label: context.l10n.t('iosNetworkInterfaces'),
      value: _iosValue(context, details?.networkInterfaces),
    ),
    _OverviewDetailData(
      label: context.l10n.t('wifi'),
      value: _iosValue(context, overview.wifi),
    ),
    _OverviewDetailData(
      label: context.l10n.t('ipAddress'),
      value: _iosValue(context, overview.ipAddress),
    ),
    _OverviewDetailData(
      label: context.l10n.t('iosHardwareMac'),
      value: _iosValue(context, overview.macAddress),
    ),
  ];
}

List<_OverviewDetailData> _iosScreenItems(
  BuildContext context,
  DeviceOverview overview,
) {
  final spec = IosModelSpec.byProductType[overview.iosDetails?.productType];
  return [
    _OverviewDetailData(
      label: context.l10n.t('iosScreenSpecResolution'),
      value: _iosValue(context, spec?.resolution),
    ),
    _OverviewDetailData(
      label: context.l10n.t('iosScreenSpecPpi'),
      value: _iosValue(context, spec == null ? null : '${spec.ppi} PPI'),
    ),
    _OverviewDetailData(
      label: context.l10n.t('iosLogicalResolution'),
      value: _iosValue(context, overview.resolution),
    ),
    _OverviewDetailData(
      label: context.l10n.t('iosDisplayScale'),
      value: context.l10n.t('iosValueUnavailable'),
    ),
    _OverviewDetailData(
      label: context.l10n.t('refreshRate'),
      value: _iosValue(context, overview.refreshRate),
    ),
  ];
}
