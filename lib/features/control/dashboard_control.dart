part of '../dashboard_screen.dart';

class _ControlTab extends ConsumerStatefulWidget {
  const _ControlTab({required this.device, required this.sessions});

  final DiscoveredDevice device;
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
    final isOnline = ref.watch(deviceOnlineProvider(widget.device.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isOnline)
          _buildOfflineWarningBanner(
            context,
            context.l10n.t('offlineControlWarning'),
          ),
        AbsorbPointer(
          absorbing: !isOnline,
          child: Opacity(
            opacity: isOnline ? 1.0 : 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _QuickActionsPanel(device: widget.device),
                const SizedBox(height: 16),
                _DeeplinkPanel(device: widget.device),
                const SizedBox(height: 16),
                _LayoutHelperPanel(device: widget.device),
                const SizedBox(height: 16),
                _SystemSettingsPanel(device: widget.device),
                const SizedBox(height: 16),
                _WifiPasswordsPanel(device: widget.device),
                const SizedBox(height: 16),
                _CertificatePanel(device: widget.device),
                const SizedBox(height: 16),
                _PowerPanel(device: widget.device),
              ],
            ),
          ),
        ),
      ],
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

  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(deviceActionServiceProvider);
    final overviewAsync = device.isOnline
        ? ref.watch(deviceOverviewProvider(device.id))
        : const AsyncValue<DeviceOverview>.loading();
    final showTouchesEnabled = overviewAsync.value?.showTouchesEnabled ?? false;
    final pointerLocationEnabled =
        overviewAsync.value?.pointerLocationEnabled ?? false;
    final demoModeEnabled = overviewAsync.value?.demoModeEnabled ?? false;
    final viewAttributeInspectionEnabled =
        overviewAsync.value?.viewAttributeInspectionEnabled ?? false;

    return _ActionCard(
      title: context.l10n.t('layoutHelper'),
      children: [
        _ToggleActionButton(
          iconOn: CupertinoIcons.square_grid_2x2,
          iconOff: CupertinoIcons.rectangle,
          label: context.l10n.t('layoutBoundsToggle'),
          value: overviewAsync.value?.layoutBoundsEnabled ?? false,
          onToggle: (on) async {
            await _runAdbAction(
              context,
              ref,
              actions.toggleLayoutBounds(device.id, on),
            );
            // 回读设备状态，更新按钮高亮及下一次点击的开关方向。
            if (context.mounted && device.isOnline) {
              ref.invalidate(deviceOverviewProvider(device.id));
            }
          },
        ),
        _ToggleActionButton(
          iconOn: CupertinoIcons.moon,
          iconOff: CupertinoIcons.sun_max,
          label: context.l10n.t('darkLightToggle'),
          onToggle: (on) =>
              _runAdbAction(context, ref, actions.setDarkMode(device.id, on)),
        ),
        _ToggleActionButton(
          iconOn: CupertinoIcons.hand_point_right_fill,
          iconOff: CupertinoIcons.hand_point_right,
          label: context.l10n.t('showTouchesToggle'),
          value: showTouchesEnabled,
          onToggle: (on) async {
            await _runAdbAction(
              context,
              ref,
              actions.setShowTouches(device.id, on),
            );
            if (device.isOnline) {
              ref.invalidate(deviceOverviewProvider(device.id));
            }
          },
        ),
        _ToggleActionButton(
          iconOn: CupertinoIcons.pencil,
          iconOff: CupertinoIcons.pencil,
          label: context.l10n.t('pointerLocationToggle'),
          value: pointerLocationEnabled,
          onToggle: (on) async {
            await _runAdbAction(
              context,
              ref,
              actions.setPointerLocation(device.id, on),
            );
            if (device.isOnline) {
              ref.invalidate(deviceOverviewProvider(device.id));
            }
          },
        ),

        _ToggleActionButton(
          iconOn: CupertinoIcons.play_rectangle_fill,
          iconOff: CupertinoIcons.play_rectangle,
          label: context.l10n.t('demoModeToggle'),
          value: demoModeEnabled,
          onToggle: (on) async {
            await _runAdbAction(
              context,
              ref,
              actions.setDemoMode(device.id, on),
            );
            if (device.isOnline) {
              ref.invalidate(deviceOverviewProvider(device.id));
            }
          },
        ),
        _ToggleActionButton(
          iconOn: CupertinoIcons.viewfinder,
          iconOff: CupertinoIcons.viewfinder,
          label: context.l10n.t('viewAttributeInspectionToggle'),
          value: viewAttributeInspectionEnabled,
          onToggle: (on) async {
            await _runAdbAction(
              context,
              ref,
              actions.setViewAttributeInspection(device.id, on),
            );
            if (device.isOnline) {
              ref.invalidate(deviceOverviewProvider(device.id));
            }
          },
        ),
      ],
    );
  }
}


class _WifiPasswordsPanel extends ConsumerWidget {
  const _WifiPasswordsPanel({required this.device});

  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRootAsync = ref.watch(isDeviceRootProvider(device.id));
    final isRoot = isRootAsync.value ?? false;

    return _ActionCard(
      title: context.l10n.t('wifiPasswordTitle'),
      children: [
        _ActionButton(
          icon: CupertinoIcons.wifi,
          label: context.l10n.t('wifiPasswordAction'),
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (context) => _WifiPasswordsDialog(deviceId: device.id),
            );
          },
        ),
        if (!isRoot && !isRootAsync.isLoading)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                CupertinoIcons.info_circle,
                size: 16,
                color: Theme.of(context).appColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.t('wifiPasswordNoRoot'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// 应用 tab 使用 StatefulWidget，因为筛选和选中项属于本地 UI 状态。
