part of 'dashboard_screen.dart';

class _ControlTab extends StatelessWidget {
  const _ControlTab({required this.device, required this.sessions});

  final AdbDevice device;
  final Map<String, ScrcpySession> sessions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _QuickActionsPanel(device: device),
        const SizedBox(height: 16),
        _LayoutHelperPanel(device: device),
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
          onToggle: (on) =>
              _runAdbAction(context, ref, actions.setWifi(device.id, on)),
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
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.l10n.t('inputText')),
          content: TextField(
            controller: controller,
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
              onPressed: () => Navigator.of(context).pop(controller.text),
            ),
          ],
        );
      },
    );
    controller.dispose();

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

/// 应用 tab 使用 StatefulWidget，因为筛选和选中项属于本地 UI 状态。
