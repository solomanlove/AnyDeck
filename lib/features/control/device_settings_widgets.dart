part of 'device_settings_popup.dart';

/// 投屏窗口与控制页复用的手机设置入口图标。
class DeviceSettingsIcon extends StatelessWidget {
  const DeviceSettingsIcon({super.key, this.color, this.size = 20});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? IconTheme.of(context).color;
    return SizedBox(
      width: max(size + 6, 24),
      height: max(size + 6, 24),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 2,
            top: 1,
            child: Icon(
              CupertinoIcons.device_phone_portrait,
              size: size,
              color: effectiveColor,
            ),
          ),
          Positioned(
            right: 1,
            bottom: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.gear_alt,
                size: size * 0.58,
                color: effectiveColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showDeviceSettingsPopup({
  required BuildContext context,
  required String deviceId,
  bool isHarmony = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        DeviceSettingsPopup(deviceId: deviceId, isHarmony: isHarmony),
  );
}

class _ShortcutSettingGrid extends StatelessWidget {
  const _ShortcutSettingGrid({required this.title, required this.actions});

  final String title;
  final List<_ShortcutSettingAction> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingLabel(title),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final action in actions)
              _ShortcutSettingButton(action: action),
          ],
        ),
      ],
    );
  }
}

class _ShortcutSettingButton extends StatelessWidget {
  const _ShortcutSettingButton({required this.action});

  final _ShortcutSettingAction action;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(action.icon, size: 16),
      label: Text(
        action.label,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
      ),
      onPressed: action.onPressed,
    );
  }
}

/// 带状态切换的水平图标按钮，供布局辅助快捷开关复用。
class _ToggleSettingButton extends StatelessWidget {
  const _ToggleSettingButton({
    required this.iconOn,
    required this.iconOff,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData iconOn;
  final IconData iconOff;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontSize: 11, fontWeight: FontWeight.bold);
    if (value) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          minimumSize: const Size(0, 34),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
        ),
        icon: Icon(iconOn, size: 16),
        label: Text(label, overflow: TextOverflow.ellipsis, style: labelStyle),
        onPressed: () => onChanged(false),
      );
    }
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: colorScheme.primary),
        foregroundColor: colorScheme.primary,
      ),
      icon: Icon(iconOff, size: 16),
      label: Text(label, overflow: TextOverflow.ellipsis, style: labelStyle),
      onPressed: () => onChanged(true),
    );
  }
}

class _SliderSettingRow extends StatelessWidget {
  const _SliderSettingRow({
    required this.label,
    required this.value,
    required this.max,
    required this.divisions,
    required this.valueText,
    required this.onChanged,
    required this.onChangeEnd,
    this.trailing,
  });

  final String label;
  final double value;
  final double max;
  final int divisions;
  final String valueText;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            Expanded(child: _SettingLabel(label)),
            SizedBox(
              width: 72,
              child: Text(
                valueText,
                textAlign: TextAlign.right,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ),
            SizedBox(width: 40, child: trailing),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: value.clamp(0, max).toDouble(),
          min: 0,
          max: max,
          divisions: divisions,
          label: valueText,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}

class _SettingLabel extends StatelessWidget {
  const _SettingLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style:
          Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ) ??
          const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
    );
  }
}
