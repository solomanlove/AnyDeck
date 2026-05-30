part of '../dashboard_screen.dart';

class _ControlTab extends ConsumerStatefulWidget {
  const _ControlTab({required this.device, required this.sessions});

  final AdbDevice device;
  final Map<String, ScrcpySession> sessions;

  @override
  ConsumerState<_ControlTab> createState() => _ControlTabState();
}

class _ControlTabState extends ConsumerState<_ControlTab> {
  @override
  void initState() {
    super.initState();
    _refreshOverview();
  }

  @override
  void didUpdateWidget(covariant _ControlTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.device.id != oldWidget.device.id) {
      _refreshOverview();
    }
  }

  void _refreshOverview() {
    if (widget.device.isOnline) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.invalidate(deviceOverviewProvider(widget.device.id));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _QuickActionsPanel(device: widget.device),
        const SizedBox(height: 16),
        _DeeplinkPanel(device: widget.device),
        const SizedBox(height: 16),
        _LayoutHelperPanel(device: widget.device),
        const SizedBox(height: 16),
        _PowerPanel(device: widget.device),
        const SizedBox(height: 16),
        _SystemSettingsPanel(device: widget.device),
      ],
    );
  }
}

/// 只读手机概览面板，数据来自 adb 属性和 sysfs/proc 读取。

class _QuickActionsPanel extends ConsumerWidget {
  const _QuickActionsPanel({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(deviceActionServiceProvider);

    final overviewAsync = device.isOnline
        ? ref.watch(deviceOverviewProvider(device.id))
        : const AsyncValue<DeviceOverview>.loading();
    final wifiEnabled = overviewAsync.value?.wifiEnabled ?? false;
    final airplaneModeEnabled = overviewAsync.value?.airplaneModeEnabled ?? false;
    final mobileDataEnabled = overviewAsync.value?.mobileDataEnabled ?? false;
    final talkbackEnabled = overviewAsync.value?.talkbackEnabled ?? false;

    return _ActionCard(
      title: context.l10n.t('deviceActions'),
      children: [
        _ActionButton(
          icon: CupertinoIcons.keyboard,
          label: context.l10n.t('inputText'),
          onPressed: () => _showInputTextDialog(context, ref, device.id),
        ),
        _ActionButton(
          icon: CupertinoIcons.home,
          label: context.l10n.t('home'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.keyEvent(device.id, 3)),
        ),
        _ActionButton(
          icon: CupertinoIcons.back,
          label: context.l10n.t('back'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.keyEvent(device.id, 4)),
        ),
        _ActionButton(
          icon: CupertinoIcons.power,
          label: context.l10n.t('power'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.keyEvent(device.id, 26)),
        ),
        _ActionButton(
          icon: CupertinoIcons.volume_up,
          label: context.l10n.t('volumeUp'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.volumeUp(device.id)),
        ),
        _ActionButton(
          icon: CupertinoIcons.volume_down,
          label: context.l10n.t('volumeDown'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.volumeDown(device.id)),
        ),
        _ToggleActionButton(
          iconOn: CupertinoIcons.wifi,
          iconOff: CupertinoIcons.wifi_slash,
          label: context.l10n.t('wifiToggle'),
          value: wifiEnabled,
          onToggle: (on) async {
            await _runAdbAction(context, ref, actions.setWifi(device.id, on));
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
            await _runAdbAction(context, ref, actions.setAirplaneMode(device.id, on));
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
            await _runAdbAction(context, ref, actions.setMobileData(device.id, on));
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
            await _runAdbAction(context, ref, actions.setTalkback(device.id, on));
            if (device.isOnline) {
              ref.invalidate(deviceOverviewProvider(device.id));
            }
          },
        ),
        _ActionButton(
          icon: CupertinoIcons.bars,
          label: context.l10n.t('menuKey'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.menuKey(device.id)),
        ),
        _ActionButton(
          icon: CupertinoIcons.bell,
          label: context.l10n.t('notificationBar'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openNotificationBar(device.id),
          ),
        ),
        _ToggleActionButton(
          iconOn: CupertinoIcons.device_phone_landscape,
          iconOff: CupertinoIcons.device_phone_portrait,
          label: context.l10n.t('autoRotateToggle'),
          onToggle: (on) =>
              _runAdbAction(context, ref, actions.setAutoRotate(device.id, on)),
        ),
        _ActionButton(
          icon: CupertinoIcons.scope,
          label: context.l10n.t('focus'),
          onPressed: () =>
              _showAdbResult(context, ref, actions.currentFocus(device.id)),
        ),
      ],
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

class _InputTextDialog extends StatefulWidget {
  const _InputTextDialog();

  @override
  State<_InputTextDialog> createState() => _InputTextDialogState();
}

class _InputTextDialogState extends State<_InputTextDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.t('inputText')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: context.l10n.t('text')),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.t('cancel')),
        ),
        FilledButton.icon(
          icon: const Icon(CupertinoIcons.paperplane),
          label: Text(context.l10n.t('send')),
          onPressed: () => Navigator.of(context).pop(_controller.text),
        ),
      ],
    );
  }
}

/// 面向开发调试的布局和主题辅助操作。
class _LayoutHelperPanel extends ConsumerWidget {
  const _LayoutHelperPanel({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(deviceActionServiceProvider);

    return _ActionCard(
      title: context.l10n.t('layoutHelper'),
      children: [
        _ToggleActionButton(
          iconOn: CupertinoIcons.square_grid_2x2,
          iconOff: CupertinoIcons.rectangle,
          label: context.l10n.t('layoutBoundsToggle'),
          onToggle: (on) => _runAdbAction(
            context,
            ref,
            actions.toggleLayoutBounds(device.id, on),
          ),
        ),
        _ToggleActionButton(
          iconOn: CupertinoIcons.moon,
          iconOff: CupertinoIcons.sun_max,
          label: context.l10n.t('darkLightToggle'),
          onToggle: (on) =>
              _runAdbAction(context, ref, actions.setDarkMode(device.id, on)),
        ),
      ],
    );
  }
}

class _DeeplinkPanel extends ConsumerWidget {
  const _DeeplinkPanel({required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(deviceActionServiceProvider);

    return _ActionCard(
      title: context.l10n.t('deeplink'),
      children: [
        _ActionButton(
          icon: CupertinoIcons.device_desktop,
          label: context.l10n.t('deeplinkDeveloperOptions'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openDeveloperSettings(device.id),
          ),
        ),
        _ActionButton(
          icon: CupertinoIcons.info,
          label: context.l10n.t('deeplinkDeviceInfo'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openDeviceInfoSettings(device.id),
          ),
        ),
        _ActionButton(
          icon: CupertinoIcons.globe,
          label: context.l10n.t('deeplinkLanguages'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openLocaleSettings(device.id),
          ),
        ),
        _ActionButton(
          icon: CupertinoIcons.settings,
          label: context.l10n.t('deeplinkSettings'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openMainSettings(device.id),
          ),
        ),
        _ActionButton(
          icon: CupertinoIcons.wifi,
          label: context.l10n.t('deeplinkWifi'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openWifiSettings(device.id),
          ),
        ),
        _ActionButton(
          icon: CupertinoIcons.square_grid_2x2,
          label: context.l10n.t('deeplinkApps'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openManageApplicationsSettings(device.id),
          ),
        ),
        _ActionButton(
          icon: CupertinoIcons.link,
          label: context.l10n.t('deeplinkCustom'),
          onPressed: () => _showCustomDeeplinkDialog(context, ref, device.id),
        ),
      ],
    );
  }

  Future<void> _showCustomDeeplinkDialog(
    BuildContext context,
    WidgetRef ref,
    String deviceId,
  ) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('deeplinkCustomTitle')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'https://... 或 myapp://...',
            labelText: context.l10n.t('deeplinkCustomHint'),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton.icon(
            icon: const Icon(CupertinoIcons.link),
            label: Text(context.l10n.t('send')),
            onPressed: () => Navigator.of(context).pop(controller.text),
          ),
        ],
      ),
    );

    controller.dispose();

    if (url == null || url.trim().isEmpty || !context.mounted) {
      return;
    }

    await _runAdbAction(
      context,
      ref,
      ref
          .read(deviceActionServiceProvider)
          .openCustomDeeplink(deviceId, url.trim()),
    );
  }
}


/// 应用 tab 使用 StatefulWidget，因为筛选和选中项属于本地 UI 状态。
