part of '../dashboard_screen.dart';

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context) {
    return _DeviceOverviewPanel(device: device);
  }
}

/// 读取设备概览数据，并交由响应式概览组件展示。
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
          : DeviceOverviewContent(
              device: device,
              overview: data,
              onRefresh: () => device.isOnline
                  ? ref.invalidate(deviceOverviewProvider(device.id))
                  : ref.invalidate(cachedDeviceOverviewProvider(device.id)),
            ),
    );
  }
}
