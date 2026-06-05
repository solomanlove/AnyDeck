part of '../dashboard_screen.dart';

class _SelectedDeviceHeader extends ConsumerWidget {
  const _SelectedDeviceHeader({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registeredDevices = ref.watch(deviceRegistryProvider);
    final matchedDevice = registeredDevices.firstWhere(
      (d) => d.id == device.id,
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

    final titleText = matchedDevice.displayName;
    final status = device.status;

    // Get background and icon colors based on status
    final Color iconBgColor;
    final Color iconColor;
    if (status == 'device') {
      iconBgColor = const Color(0xFFE2F7EB); // Soft mint green
      iconColor = const Color(0xFF2EC46B); // Rich green
    } else if (status == 'unauthorized') {
      iconBgColor = const Color(0xFFFFF3E0); // Soft orange
      iconColor = const Color(0xFFE65100); // Rich orange
    } else {
      iconBgColor = const Color(0xFFF5F5F5); // Soft gray
      iconColor = const Color(0xFF9E9E9E); // Gray
    }

    final String? logoAsset = overviewAsync.hasValue
        ? BrandLogoHelper.getBrandLogoAsset(overviewAsync.value!.brand)
        : null;

    final Widget avatarChild;
    if (logoAsset != null) {
      Widget logoImage = Image.asset(
        logoAsset,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
      if (status != 'device') {
        logoImage = ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Colors.grey,
            BlendMode.saturation,
          ),
          child: Opacity(opacity: 0.6, child: logoImage),
        );
      }
      avatarChild = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: logoImage,
      );
    } else {
      avatarChild = Center(
        child: Icon(
          CupertinoIcons.device_phone_portrait,
          size: 32,
          color: iconColor,
        ),
      );
    }

    final avatar = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: logoAsset != null ? Colors.white : iconBgColor,
        borderRadius: BorderRadius.circular(16),
        border: logoAsset != null
            ? Border.all(color: iconBgColor, width: 2)
            : null,
      ),
      child: avatarChild,
    );

    final isNetwork = matchedDevice.isNetwork;

    final statusAndConnectionRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isNetwork ? Icons.wifi : Icons.usb,
          size: 16,
          color: const Color(0xFF757575),
        ),
        const SizedBox(width: 4),
        Text(
          isNetwork ? 'Wi-Fi' : 'USB',
          style: const TextStyle(
            color: Color(0xFF757575),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );

    final title = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: titleText,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xff202124),
                  fontSize: 20,
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        statusAndConnectionRow,
      ],
    );

    final closeButton = IconButton(
      icon: const Icon(CupertinoIcons.xmark),
      tooltip: context.l10n.t('close'),
      onPressed: () {
        ref.read(userClearedDeviceSelectionProvider.notifier).state = true;
        ref.read(selectedDeviceProvider.notifier).clear();
      },
    );

    return DragToMoveArea(
      child: Container(
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Color(0xffeceef1), width: 1),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 260) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    avatar,
                    const SizedBox(width: 14),
                    SizedBox(width: 160, child: title),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(CupertinoIcons.macwindow),
                      tooltip: '独立窗口投屏',
                      onPressed: device.isOnline
                          ? () => _openStandaloneMirror(context, ref, device)
                          : null,
                    ),
                    // const SizedBox(width: 8),
                    // IconButton(
                    //   icon: const Icon(Icons.open_in_new),
                    //   tooltip: '系统原生投屏(支持音频)',
                    //   onPressed: device.isOnline
                    //       ? () => _openExternalMirror(context, ref, device.id)
                    //       : null,
                    // ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.settings_remote),
                      tooltip: context.l10n.t('remoteController'),
                      onPressed: device.isOnline
                          ? () => showDialog<void>(
                              context: context,
                              builder: (_) =>
                                  _RemoteControllerDialog(device: device),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    closeButton,
                  ],
                ),
              );
            }

            return Row(
              children: [
                avatar,
                const SizedBox(width: 14),
                Expanded(child: title),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(CupertinoIcons.macwindow),
                  tooltip: '投屏',
                  onPressed: device.isOnline
                      ? () => _openStandaloneMirror(context, ref, device)
                      : null,
                ),
                // const SizedBox(width: 8),
                // IconButton(
                //   icon: const Icon(Icons.open_in_new),
                //   tooltip: '系统原生投屏(支持音频)',
                //   onPressed: device.isOnline
                //       ? () => _openExternalMirror(context, ref, device.id)
                //       : null,
                // ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.settings_remote),
                  tooltip: context.l10n.t('remoteController'),
                  onPressed: device.isOnline
                      ? () => showDialog<void>(
                          context: context,
                          builder: (_) =>
                              _RemoteControllerDialog(device: device),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                closeButton,
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openStandaloneMirror(
    BuildContext context,
    WidgetRef ref,
    AdbDevice device,
  ) async {
    // 1. If mirroring is active, stop it first.
    final textureId = ref.read(activeEmbeddedMirrorProvider(device.id));
    if (textureId != null) {
      await ref
          .read(activeEmbeddedMirrorProvider(device.id).notifier)
          .forceStop();
    }

    // 2. Open the standalone mirroring window
    try {
      final window = await DesktopMultiWindow.createWindow(
        jsonEncode({
          'type': 'mirror',
          'deviceId': device.id,
          'deviceName': device.model ?? device.id,
        }),
      );
      await window.setFrame(const Offset(100, 100) & const Size(480, 800));
      await window.center();
      await window.setTitle('投屏 - ${device.model ?? device.id}');
      await window.show();
    } catch (e) {
      debugPrint('Failed to open standalone mirror window: $e');
    }
  }

  // ignore: unused_element
  Future<void> _openExternalMirror(
    BuildContext context,
    WidgetRef ref,
    String deviceId,
  ) async {
    // 1. If embedded mirroring is active, stop it first.
    final textureId = ref.read(activeEmbeddedMirrorProvider(deviceId));
    if (textureId != null) {
      await ref
          .read(activeEmbeddedMirrorProvider(deviceId).notifier)
          .forceStop();
    }

    try {
      final settings = ref.read(appSettingsProvider);
      final bitrateMbps = (settings.mirrorVideoBitrate / 1000000).round();
      final options = ScrcpyLaunchOptions(
        maxSize: settings.mirrorMaxSize == 0 ? 1920 : settings.mirrorMaxSize,
        videoBitRate: '${bitrateMbps}M',
        alwaysOnTop: settings.scrcpyAlwaysOnTop,
        noAudio: !settings.mirrorAudioEnabled,
      );

      final session = await ref
          .read(scrcpyServiceProvider)
          .start(deviceId: deviceId, options: options);
      ref.read(scrcpySessionsProvider.notifier).add(session);

      if (context.mounted) {
        _showSnack(context, '已成功开启系统原生投屏，音频同步转发');
      }
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, '启动外部原生投屏失败: $e', isError: true);
      }
    }
  }
}
