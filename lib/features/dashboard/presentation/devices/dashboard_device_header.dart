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
    final textureId = ref.watch(activeEmbeddedMirrorProvider(device.id));
    final isMirrorActive = textureId != null;

    final String subtitleText;
    if (overviewAsync.hasValue) {
      final overview = overviewAsync.value!;
      final brand = overview.brand.trim();
      final model = overview.model.trim();

      if (model.isNotEmpty && model != '-') {
        final cleanModel = model.replaceAll('_', ' ');
        if (brand.isNotEmpty && brand != '-' && brand.toLowerCase() != 'unknown') {
          if (cleanModel.toLowerCase().contains(brand.toLowerCase())) {
            subtitleText = cleanModel;
          } else {
            final capitalizedBrand = brand[0].toUpperCase() + brand.substring(1);
            subtitleText = '$capitalizedBrand $cleanModel';
          }
        } else {
          subtitleText = cleanModel;
        }
      } else {
        subtitleText = matchedDevice.model?.replaceAll('_', ' ') ?? device.displayName;
      }
    } else {
      subtitleText = matchedDevice.model?.replaceAll('_', ' ') ?? device.displayName;
    }

    final titleText = matchedDevice.displayName;
    final status = device.status;

    // Get background and icon colors based on status
    final Color iconBgColor;
    final Color iconColor;
    if (status == 'device') {
      iconBgColor = const Color(0xFFE2F7EB); // Soft mint green
      iconColor = const Color(0xFF2EC46B);   // Rich green
    } else if (status == 'unauthorized') {
      iconBgColor = const Color(0xFFFFF3E0); // Soft orange
      iconColor = const Color(0xFFE65100);   // Rich orange
    } else {
      iconBgColor = const Color(0xFFF5F5F5); // Soft gray
      iconColor = const Color(0xFF9E9E9E);   // Gray
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
          child: Opacity(
            opacity: 0.6,
            child: logoImage,
          ),
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

    // Status text
    final String statusText;
    if (status == 'device') {
      statusText = context.l10n.t('deviceOnline');
    } else if (status == 'unauthorized') {
      statusText = context.l10n.t('deviceUnauthorized');
    } else {
      statusText = context.l10n.t('deviceOffline');
    }

    // Status colors
    final Color statusBgColor;
    final Color statusTextColor;
    if (status == 'device') {
      statusBgColor = const Color(0xFF2EC46B); // Solid green
      statusTextColor = Colors.white;
    } else if (status == 'unauthorized') {
      statusBgColor = const Color(0xFFFFF3E0);
      statusTextColor = const Color(0xFFE65100);
    } else {
      statusBgColor = const Color(0xFFECEEF1);
      statusTextColor = const Color(0xFF757575);
    }

    final isNetwork = matchedDevice.isNetwork;

    final statusAndConnectionRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusBgColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            statusText,
            style: TextStyle(
              color: statusTextColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
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
        const SizedBox(width: 12),
        _buildRootPill(context, ref, device.id, device.isOnline),
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
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: SizedBox(width: 6),
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _showRenameDialog(context, ref, matchedDevice),
                    child: const Icon(
                      CupertinoIcons.pencil,
                      size: 14,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          subtitleText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: const Color(0xff5f6368),
            fontSize: 13,
          ),
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
        height: 112,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xffeceef1), width: 1)),
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
                      icon: const Icon(Icons.terminal),
                      tooltip: context.l10n.t('terminalDir'),
                      onPressed: () => _openLocalTerminal(context, ref),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        isMirrorActive ? CupertinoIcons.tv_fill : CupertinoIcons.tv,
                        color: isMirrorActive ? const Color(0xFF2EC46B) : null,
                      ),
                      tooltip: isMirrorActive ? '停止投屏' : '内嵌投屏',
                      onPressed: device.isOnline
                          ? () => _toggleEmbeddedScrcpy(context, ref, device.id)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(CupertinoIcons.gamecontroller),
                      tooltip: context.l10n.t('remoteController'),
                      onPressed: device.isOnline
                          ? () => showDialog<void>(
                                context: context,
                                builder: (_) => _RemoteControllerDialog(device: device),
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
                  icon: const Icon(Icons.terminal),
                  tooltip: context.l10n.t('terminalDir'),
                  onPressed: () => _openLocalTerminal(context, ref),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    isMirrorActive ? CupertinoIcons.tv_fill : CupertinoIcons.tv,
                    color: isMirrorActive ? const Color(0xFF2EC46B) : null,
                  ),
                  tooltip: isMirrorActive ? '停止投屏' : '内嵌投屏',
                  onPressed: device.isOnline
                      ? () => _toggleEmbeddedScrcpy(context, ref, device.id)
                      : null,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(CupertinoIcons.gamecontroller),
                  tooltip: context.l10n.t('remoteController'),
                  onPressed: device.isOnline
                      ? () => showDialog<void>(
                            context: context,
                            builder: (_) => _RemoteControllerDialog(device: device),
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

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    RegisteredDevice device,
  ) async {
    final controller = TextEditingController(
      text: device.customName ?? device.model ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.t('editDeviceName')),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: context.l10n.t('enterDeviceName'),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: Text(context.l10n.t('confirm')),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (name != null && context.mounted) {
      await ref
          .read(deviceRegistryProvider.notifier)
          .setAlias(device.id, name);
    }
  }

  Future<void> _toggleEmbeddedScrcpy(
    BuildContext context,
    WidgetRef ref,
    String deviceId,
  ) async {
    try {
      await ref
          .read(activeEmbeddedMirrorProvider(deviceId).notifier)
          .toggleMirroring();
    } on Object catch (error) {
      if (context.mounted) {
        _showSnack(context, error.toString(), isError: true);
      }
    }
  }

  /// 启动 scrcpy，并将返回的进程元数据记录 to Riverpod 状态。
  Future<void> _startScrcpy(
    BuildContext context,
    WidgetRef ref,
    String deviceId,
  ) async {
    try {
      final session = await ref
          .read(scrcpyServiceProvider)
          .start(deviceId: deviceId, options: const ScrcpyLaunchOptions());
      ref.read(scrcpySessionsProvider.notifier).add(session);
      if (context.mounted) {
        _showSnack(
          context,
          '${context.l10n.t('scrcpyStarted')}: PID ${session.pid}',
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showSnack(context, error.toString(), isError: true);
      }
    }
  }

  Widget _buildRootPill(BuildContext context, WidgetRef ref, String deviceId, bool isOnline) {
    final isRootAsync = ref.watch(isDeviceRootProvider(deviceId));
    return isRootAsync.when(
      data: (isRoot) {
        final text = isRoot ? context.l10n.t('rooted') : context.l10n.t('unrooted');
        final color = isRoot ? const Color(0xFF2EC46B) : const Color(0xFFE65100);
        final bgColor = isRoot ? const Color(0xFFE2F7EB) : const Color(0xFFFFF3E0);

        return Tooltip(
          message: isRoot ? context.l10n.t('rooted') : context.l10n.t('enterRootMode'),
          child: Material(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: isOnline && !isRoot
                  ? () => _toggleRoot(context, ref, deviceId)
                  : null,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isRoot ? CupertinoIcons.lock_open_fill : CupertinoIcons.lock_fill,
                      size: 12,
                      color: color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      text,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, stack) => const Icon(CupertinoIcons.question, size: 14, color: Colors.grey),
    );
  }

  Future<void> _toggleRoot(BuildContext context, WidgetRef ref, String deviceId) async {
    try {
      _showSnack(context, context.l10n.t('enteringRootMode'));
      final adb = ref.read(adbServiceProvider);
      final res = await adb.run(['-s', deviceId, 'root']);
      if (!context.mounted) return;
      if (res.isSuccess) {
        _showSnack(context, res.stdout.isNotEmpty ? res.stdout.trim() : context.l10n.t('enterRootModeSuccess'));
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (!context.mounted) return;
        ref.invalidate(isDeviceRootProvider(deviceId));
      } else {
        _showSnack(context, res.stderr.isNotEmpty ? res.stderr.trim() : 'Failed to enter root mode', isError: true);
      }
    } catch (e) {
      if (!context.mounted) return;
      _showSnack(context, e.toString(), isError: true);
    }
  }

  Future<void> _openLocalTerminal(BuildContext context, WidgetRef ref) async {
    try {
      final adbPath = ref.read(adbServiceProvider).executable;
      String dirPath = Directory.current.path;
      if (adbPath != 'adb') {
        final adbFile = File(adbPath);
        if (adbFile.existsSync()) {
          dirPath = adbFile.parent.path;
        }
      }
      
      if (Platform.isMacOS) {
        await Process.run('open', ['-a', 'Terminal', dirPath]);
      } else if (Platform.isWindows) {
        await Process.run('cmd.exe', ['/c', 'start', 'cmd.exe'], workingDirectory: dirPath);
      } else if (Platform.isLinux) {
        await Process.run('x-terminal-emulator', [], workingDirectory: dirPath);
      }
      if (context.mounted) {
        _showSnack(context, '${context.l10n.t('terminalDir')}: $dirPath');
      }
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, 'Failed to open terminal: $e', isError: true);
      }
    }
  }
}
