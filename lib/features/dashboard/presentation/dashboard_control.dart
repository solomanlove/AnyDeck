part of 'dashboard_screen.dart';

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

    return _ActionCard(
      title: context.l10n.t('deviceActions'),
      children: [
        _ActionButton(
          icon: Icons.keyboard,
          label: context.l10n.t('inputText'),
          onPressed: () => _showInputTextDialog(context, ref, device.id),
        ),
        _ActionButton(
          icon: Icons.home,
          label: context.l10n.t('home'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.keyEvent(device.id, 3)),
        ),
        _ActionButton(
          icon: Icons.arrow_back,
          label: context.l10n.t('back'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.keyEvent(device.id, 4)),
        ),
        _ActionButton(
          icon: Icons.power_settings_new,
          label: context.l10n.t('power'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.keyEvent(device.id, 26)),
        ),
        _ActionButton(
          icon: Icons.volume_up,
          label: context.l10n.t('volumeUp'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.volumeUp(device.id)),
        ),
        _ActionButton(
          icon: Icons.volume_down,
          label: context.l10n.t('volumeDown'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.volumeDown(device.id)),
        ),
        _ToggleActionButton(
          iconOn: Icons.wifi,
          iconOff: Icons.wifi_off,
          label: context.l10n.t('wifiToggle'),
          value: wifiEnabled,
          onToggle: (on) async {
            await _runAdbAction(context, ref, actions.setWifi(device.id, on));
            if (device.isOnline) {
              ref.invalidate(deviceOverviewProvider(device.id));
            }
          },
        ),
        _ActionButton(
          icon: Icons.menu,
          label: context.l10n.t('menuKey'),
          onPressed: () =>
              _runAdbAction(context, ref, actions.menuKey(device.id)),
        ),
        _ActionButton(
          icon: Icons.notifications_active,
          label: context.l10n.t('notificationBar'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openNotificationBar(device.id),
          ),
        ),
        _ToggleActionButton(
          iconOn: Icons.screen_rotation,
          iconOff: Icons.screen_lock_rotation,
          label: context.l10n.t('autoRotateToggle'),
          onToggle: (on) =>
              _runAdbAction(context, ref, actions.setAutoRotate(device.id, on)),
        ),
        _ActionButton(
          icon: Icons.center_focus_strong,
          label: context.l10n.t('focus'),
          onPressed: () =>
              _showAdbResult(context, ref, actions.currentFocus(device.id)),
        ),
        _ActionButton(
          icon: Icons.restart_alt,
          label: context.l10n.t('reboot'),
          onPressed: () async {
            final confirmed = await _confirm(
              context,
              context.l10n.t('rebootDevice'),
            );
            if (confirmed && context.mounted) {
              await _runAdbAction(context, ref, actions.reboot(device.id));
            }
          },
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
          icon: const Icon(Icons.send),
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
          iconOn: Icons.border_outer,
          iconOff: Icons.border_clear,
          label: context.l10n.t('layoutBoundsToggle'),
          onToggle: (on) => _runAdbAction(
            context,
            ref,
            actions.toggleLayoutBounds(device.id, on),
          ),
        ),
        _ToggleActionButton(
          iconOn: Icons.dark_mode,
          iconOff: Icons.light_mode,
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
          icon: Icons.developer_mode,
          label: context.l10n.t('deeplinkDeveloperOptions'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openDeveloperSettings(device.id),
          ),
        ),
        _ActionButton(
          icon: Icons.info_outline,
          label: context.l10n.t('deeplinkDeviceInfo'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openDeviceInfoSettings(device.id),
          ),
        ),
        _ActionButton(
          icon: Icons.language,
          label: context.l10n.t('deeplinkLanguages'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openLocaleSettings(device.id),
          ),
        ),
        _ActionButton(
          icon: Icons.settings,
          label: context.l10n.t('deeplinkSettings'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openMainSettings(device.id),
          ),
        ),
        _ActionButton(
          icon: Icons.wifi,
          label: context.l10n.t('deeplinkWifi'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openWifiSettings(device.id),
          ),
        ),
        _ActionButton(
          icon: Icons.apps,
          label: context.l10n.t('deeplinkApps'),
          onPressed: () => _runAdbAction(
            context,
            ref,
            actions.openManageApplicationsSettings(device.id),
          ),
        ),
        _ActionButton(
          icon: Icons.link,
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
            icon: const Icon(Icons.open_in_browser),
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
