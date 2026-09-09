part of '../dashboard_screen.dart';

/// 左侧导航顶部身份区：选中设备时替换 App logo，同时保留返回设备管理的点击入口。
class _RailIdentity extends ConsumerWidget {
  const _RailIdentity({
    required this.selectedDevice,
    required this.registeredDevices,
    required this.isNarrow,
  });

  final AdbDevice? selectedDevice;
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
      ),
    );
    final overviewAsync = ref.watch(deviceOverviewProvider(device.id));
    final mirrorAudioEnabled = ref.watch(
      appSettingsProvider.select((settings) => settings.mirrorAudioEnabled),
    );
    final sdkVersion = ref.watch(deviceSdkVersionProvider(device.id)) ?? 0;
    final isAudioForwarded = sdkVersion >= 30 && mirrorAudioEnabled;
    final logoAsset = overviewAsync.hasValue
        ? BrandLogoHelper.getBrandLogoAsset(overviewAsync.value!.brand)
        : null;
    final isNetwork = matchedDevice.isNetwork;
    final connectionLabel = isNetwork ? 'Wi-Fi' : 'USB';

    final identity = isNarrow
        ? _buildDeviceAvatar(device, logoAsset, 50)
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildDeviceAvatar(device, logoAsset, 36),
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
                                  ?.copyWith(fontWeight: FontWeight.w800),
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
                            isNetwork ? Icons.wifi : Icons.usb,
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
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

    return Tooltip(
      message: '${matchedDevice.displayName} · $connectionLabel',
      child: identity,
    );
  }

  Widget _buildAppIdentity(BuildContext context) {
    if (isNarrow) {
      return const SizedBox(
        width: 50,
        height: 50,
        child: Image(image: AssetImage(AppIcons.appLogo)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Image(image: AssetImage(AppIcons.appLogo)),
            ),
          ),
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
    );
  }

  Widget _buildDeviceAvatar(AdbDevice device, String? logoAsset, double size) {
    final Color backgroundColor;
    final Color iconColor;
    if (device.status == 'device') {
      backgroundColor = const Color(0xFFE2F7EB);
      iconColor = const Color(0xFF2EC46B);
    } else if (device.status == 'unauthorized') {
      backgroundColor = const Color(0xFFFFF3E0);
      iconColor = const Color(0xFFE65100);
    } else {
      backgroundColor = const Color(0xFFF5F5F5);
      iconColor = const Color(0xFF9E9E9E);
    }

    Widget child;
    if (logoAsset == null) {
      child = Icon(
        CupertinoIcons.device_phone_portrait,
        size: size * 0.58,
        color: iconColor,
      );
    } else {
      child = Image.asset(
        logoAsset,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: logoAsset == null ? backgroundColor : Colors.white,
        borderRadius: BorderRadius.circular(size * 0.24),
        border: logoAsset == null
            ? null
            : Border.all(color: backgroundColor, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: child,
    );
  }
}
