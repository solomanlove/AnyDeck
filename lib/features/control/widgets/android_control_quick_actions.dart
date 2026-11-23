part of '../../dashboard_screen.dart';

/// 将设备交互、系统开关和投屏采集按用途分组。
class _QuickActionsPanel extends ConsumerWidget {
  const _QuickActionsPanel({required this.device});

  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(deviceActionServiceProvider);

    final overviewAsync = device.isOnline
        ? ref.watch(deviceOverviewProvider(device.id))
        : const AsyncValue<DeviceOverview>.loading();
    final wifiEnabled = overviewAsync.value?.wifiEnabled ?? false;
    final airplaneModeEnabled =
        overviewAsync.value?.airplaneModeEnabled ?? false;
    final mobileDataEnabled = overviewAsync.value?.mobileDataEnabled ?? false;
    final talkbackEnabled = overviewAsync.value?.talkbackEnabled ?? false;

    // 仅收紧本卡按钮的左右内边距，保留原有点击高度和主题状态。
    final theme = Theme.of(context);
    const buttonPadding = WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
    final buttonTheme = theme.copyWith(
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
            .copyWith(padding: buttonPadding),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: (theme.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
          padding: buttonPadding,
        ),
      ),
    );
    return Theme(
      data: buttonTheme,
      child: _ActionCard(
        title: context.l10n.t('deviceActions'),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ControlActionGroup(
                key: const ValueKey('controlDeviceInteraction'),
                title: context.l10n.t('controlDeviceInteraction'),
                children: [
                  _ActionButton(
                    icon: CupertinoIcons.device_phone_portrait,
                    label: context.l10n.t('deviceSettings'),
                    onPressed: () => showDeviceSettingsPopup(
                      context: context,
                      deviceId: device.id,
                    ),
                  ),
                  _ActionButton(
                    icon: CupertinoIcons.keyboard,
                    label: context.l10n.t('inputText'),
                    onPressed: () =>
                        _showInputTextDialog(context, ref, device.id),
                  ),
                  _ActionButton(
                    icon: CupertinoIcons.bell,
                    label: context.l10n.t('controlShowNotifications'),
                    onPressed: () {
                      _runAdbAction(
                        context,
                        ref,
                        ref.read(adbServiceProvider).run([
                          '-s',
                          device.id,
                          'shell',
                          'cmd',
                          'statusbar',
                          'expand-notifications',
                        ]),
                      );
                    },
                  ),
                  _ActionButton(
                    icon: CupertinoIcons.slider_horizontal_3,
                    label: context.l10n.t('expandSettings'),
                    onPressed: () {
                      _runAdbAction(
                        context,
                        ref,
                        actions.openQuickSettings(device.id),
                      );
                    },
                  ),
                  _ActionButton(
                    icon: CupertinoIcons.scope,
                    label: context.l10n.t('focus'),
                    onPressed: () => _showAdbResult(
                      context,
                      ref,
                      actions.currentFocus(device.id),
                      dialogBuilder: (result) =>
                          AndroidForegroundWindowDialog(result: result),
                    ),
                  ),
                  if (!device.isIos)
                    _buildDeviceLockAction(context, ref, device),
                  if (!device.isIos)
                    _ActionButton(
                      icon: Icons.settings_remote,
                      label: context.l10n.t('remoteController'),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => RemoteControllerDialog(device: device),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _ControlActionGroup(
                key: const ValueKey('controlSystemToggles'),
                title: context.l10n.t('controlSystemToggles'),
                children: [
                  _ToggleActionButton(
                    iconOn: CupertinoIcons.wifi,
                    iconOff: CupertinoIcons.wifi_slash,
                    label: context.l10n.t('wifiToggle'),
                    value: wifiEnabled,
                    onToggle: (on) async {
                      await _runAdbAction(
                        context,
                        ref,
                        actions.setWifi(device.id, on),
                      );
                      if (device.isOnline) {
                        ref.invalidate(deviceOverviewProvider(device.id));
                      }
                    },
                  ),
                  _ToggleActionButton(
                    iconOn: CupertinoIcons.airplane,
                    iconOff: CupertinoIcons.airplane,
                    label: context.l10n.t('airplaneModeToggle'),
                    value: airplaneModeEnabled,
                    onToggle: (on) async {
                      await _runAdbAction(
                        context,
                        ref,
                        actions.setAirplaneMode(device.id, on),
                      );
                      if (device.isOnline) {
                        ref.invalidate(deviceOverviewProvider(device.id));
                      }
                    },
                  ),
                  _ToggleActionButton(
                    iconOn: CupertinoIcons.antenna_radiowaves_left_right,
                    iconOff: CupertinoIcons.antenna_radiowaves_left_right,
                    label: context.l10n.t('mobileDataToggle'),
                    value: mobileDataEnabled,
                    onToggle: (on) async {
                      await _runAdbAction(
                        context,
                        ref,
                        actions.setMobileData(device.id, on),
                      );
                      if (device.isOnline) {
                        ref.invalidate(deviceOverviewProvider(device.id));
                      }
                    },
                  ),
                  _ToggleActionButton(
                    iconOn: CupertinoIcons.volume_up,
                    iconOff: CupertinoIcons.volume_mute,
                    label: context.l10n.t('talkbackToggle'),
                    value: talkbackEnabled,
                    onToggle: (on) async {
                      await _runAdbAction(
                        context,
                        ref,
                        actions.setTalkback(device.id, on),
                      );
                      if (device.isOnline) {
                        ref.invalidate(deviceOverviewProvider(device.id));
                      }
                    },
                  ),
                  _ToggleActionButton(
                    iconOn: CupertinoIcons.device_phone_landscape,
                    iconOff: CupertinoIcons.device_phone_portrait,
                    label: context.l10n.t('autoRotateToggle'),
                    onToggle: (on) => _runAdbAction(
                      context,
                      ref,
                      actions.setAutoRotate(device.id, on),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ControlActionGroup(
                key: const ValueKey('controlMirrorCapture'),
                title: context.l10n.t('controlMirrorCapture'),
                children: [
                  _ActionButton(
                    icon: Icons.cast,
                    label: context.l10n.t('screenMirror'),
                    onPressed: () =>
                        openStandaloneMirrorWindow(context, ref, device),
                  ),
                  if (!device.isIos)
                    ...buildDeviceCaptureActions(
                      context,
                      ref,
                      device,
                      includeLockScreen: false,
                    ),
                  if (!device.isIos && !device.isHarmony)
                    _ActionButton(
                      icon: CupertinoIcons.videocam,
                      label: context.l10n.t('cameraTitle'),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            CameraPreviewDialog(deviceId: device.id),
                      ),
                    ),
                  if (!device.isIos) AudioForwardButton(device: device),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 输入文本，并通过 adb input 发送到设备。
  Future<void> _showInputTextDialog(
    BuildContext context,
    WidgetRef ref,
    String deviceId,
  ) async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _InputTextDialog(),
    );

    if (text == null || text.isEmpty || !context.mounted) {
      return;
    }
    await _runAdbAction(
      context,
      ref,
      ref.read(deviceActionServiceProvider).inputText(deviceId, text),
    );
  }
}

/// 每组沿用同一左边线，按钮按可用宽度换行。
class _ControlActionGroup extends StatelessWidget {
  const _ControlActionGroup({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: children),
      ],
    );
  }
}
