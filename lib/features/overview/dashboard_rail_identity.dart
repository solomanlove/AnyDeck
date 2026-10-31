part of '../dashboard_screen.dart';

/// 左侧导航顶部身份区：选中设备时替换 App logo，同时保留返回设备管理的点击入口。
class _RailIdentity extends ConsumerWidget {
  const _RailIdentity({
    required this.selectedDevice,
    required this.registeredDevices,
    required this.isNarrow,
  });

  final DiscoveredDevice? selectedDevice;
  final List<RegisteredDevice> registeredDevices;
  final bool isNarrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = selectedDevice;
    if (device == null) {
      return _buildAppIdentity(context);
    }

    final matchedDevice = registeredDevices.firstWhere(
      (registeredDevice) => registeredDevice.id == device.id,
      orElse: () => RegisteredDevice(
        id: device.id,
        status: device.status,
        model: device.model,
        product: device.product,
        transportId: device.transportId,
        isOnline: device.isOnline,
        serial: device.id,
        isIos: device.isIos,
        isHarmony: device.isHarmony,
        iosConnectionTypes: device.iosConnectionTypes,
      ),
    );
    final mirrorAudioEnabled = ref.watch(
      appSettingsProvider.select((settings) => settings.mirrorAudioEnabled),
    );
    final sdkVersion = ref.watch(deviceSdkVersionProvider(device.id)) ?? 0;
    final isAudioForwarded = sdkVersion >= 30 && mirrorAudioEnabled;
    final isNetwork = matchedDevice.isNetwork;
    final isUnknown = matchedDevice.isIos && matchedDevice.iosConnectionTypes.isEmpty;
    final connectionLabel = isUnknown
        ? context.l10n.t('connectionUnknown')
        : matchedDevice.hasIosNetworkConnection && matchedDevice.hasUsbConnection
            ? context.l10n.t('connectionUsbAndNetwork')
            : isNetwork ? 'Wi-Fi' : 'USB';

    final identity = isNarrow
        ? DeviceStatusAvatar(
            device: matchedDevice,
            size: 50,
            showTooltip: false,
          )
        : SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  DeviceStatusAvatar(
                    device: matchedDevice,
                    size: 36,
                    showTooltip: false,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                matchedDevice.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      height: 1.2,
                                    ),
                              ),
                            ),
                            if (isAudioForwarded) ...[
                              const SizedBox(width: 4),
                              Tooltip(
                                message: context.l10n.t('audioForwardingTooltip'),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              isUnknown ? Icons.help_outline : isNetwork ? Icons.wifi : Icons.usb,
                              size: 14,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              connectionLabel,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                    height: 1.2,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );

    return Tooltip(
      message: '${matchedDevice.displayName} · $connectionLabel (${context.l10n.t('devices')})',
      child: identity,
    );
  }

  Widget _buildAppIdentity(BuildContext context) {
    final double size = isNarrow ? 50.0 : 36.0;
    final radius = size == 36 ? 8.0 : 12.0;
    final avatar = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: const Image(image: AssetImage(AppIcons.appLogo)),
      ),
    );

    if (isNarrow) {
      return avatar;
    }

    return SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.t('appTitle'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
