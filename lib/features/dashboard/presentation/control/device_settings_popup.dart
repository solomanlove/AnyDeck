import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../../../core/adb/adb_result.dart';
import '../../../../core/device_info/device_overview.dart';
import '../../../../core/providers/app_providers.dart';
import '../widgets/dashboard_snack.dart';

/// 投屏窗口与控制 Tab 复用的手机快捷设置弹窗。
class DeviceSettingsPopup extends ConsumerStatefulWidget {
  const DeviceSettingsPopup({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<DeviceSettingsPopup> createState() =>
      _DeviceSettingsPopupState();
}

class _DeviceSettingsPopupState extends ConsumerState<DeviceSettingsPopup> {
  static const List<double> _fontScaleValues = [0.80, 1.00, 1.20, 1.40, 1.60];
  static const List<int> _densityValues = [280, 320, 360, 400, 440, 480, 560];

  bool _darkModeEnabled = false;
  double? _fontScaleIndex;
  double? _densityIndex;

  int? _parseDpi(String resolutionText) {
    final match = RegExp(r'\((\d+)dpi\)').firstMatch(resolutionText);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  int _nearestDensityIndex(int? dpi) {
    if (dpi == null) {
      return 3;
    }
    var nearestIndex = 0;
    var nearestDistance = double.infinity;
    for (var i = 0; i < _densityValues.length; i++) {
      final distance = (_densityValues[i] - dpi).abs().toDouble();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }
    return nearestIndex;
  }

  int _nearestFontScaleIndex(double scale) {
    var nearestIndex = 1;
    var nearestDistance = double.infinity;
    for (var i = 0; i < _fontScaleValues.length; i++) {
      final distance = (_fontScaleValues[i] - scale).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }
    return nearestIndex;
  }

  Future<void> _runAction(Future<AdbResult> future) async {
    final result = await future;
    if (!mounted) {
      return;
    }
    DashboardSnack.show(context, result.message, isError: !result.isSuccess);
    if (result.isSuccess) {
      ref.invalidate(deviceOverviewProvider(widget.deviceId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final overviewAsync = ref.watch(deviceOverviewProvider(widget.deviceId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xff1e1e1e) : Colors.white;

    return AlertDialog(
      backgroundColor: cardColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          Icon(
            Icons.settings,
            color: isDark ? Colors.white70 : Colors.black87,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            context.l10n.t('deviceSettings'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: overviewAsync.when(
            loading: () => const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => SizedBox(
              height: 180,
              child: Center(
                child: Text(error.toString(), textAlign: TextAlign.center),
              ),
            ),
            data: (overview) => _buildSettings(context, overview),
          ),
        ),
      ),
    );
  }

  Widget _buildSettings(BuildContext context, DeviceOverview overview) {
    final actions = ref.read(deviceActionServiceProvider);
    final fontScale =
        double.tryParse(overview.fontScale.replaceAll('x', '')) ?? 1.0;
    final fontIndex =
        _fontScaleIndex ?? _nearestFontScaleIndex(fontScale).toDouble();
    final dpi = _parseDpi(overview.resolution);
    final densityIndex = _densityIndex ?? _nearestDensityIndex(dpi).toDouble();
    final shortcutActions = [
      _ShortcutSettingAction(
        icon: Icons.developer_mode,
        label: context.l10n.t('deeplinkDeveloperOptions'),
        onPressed: () =>
            _runAction(actions.openDeveloperSettings(widget.deviceId)),
      ),
      _ShortcutSettingAction(
        icon: CupertinoIcons.wifi,
        label: context.l10n.t('deeplinkWifi'),
        onPressed: () => _runAction(actions.openWifiSettings(widget.deviceId)),
      ),
      _ShortcutSettingAction(
        icon: CupertinoIcons.settings,
        label: context.l10n.t('deeplinkSettings'),
        onPressed: () => _runAction(actions.openMainSettings(widget.deviceId)),
      ),
      _ShortcutSettingAction(
        icon: CupertinoIcons.info_circle,
        label: context.l10n.t('deeplinkDeviceInfo'),
        onPressed: () =>
            _runAction(actions.openDeviceInfoSettings(widget.deviceId)),
      ),
      _ShortcutSettingAction(
        icon: CupertinoIcons.globe,
        label: context.l10n.t('deeplinkLanguages'),
        onPressed: () =>
            _runAction(actions.openLocaleSettings(widget.deviceId)),
      ),
      _ShortcutSettingAction(
        icon: CupertinoIcons.square_grid_2x2,
        label: context.l10n.t('deeplinkApps'),
        onPressed: () =>
            _runAction(actions.openManageApplicationsSettings(widget.deviceId)),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ShortcutSettingGrid(
          title: context.l10n.t('deeplink'),
          actions: shortcutActions,
        ),
        const SizedBox(height: 14),
        _SwitchSettingRow(
          label: context.l10n.t('darkLightToggle'),
          value: _darkModeEnabled,
          onChanged: (value) async {
            setState(() => _darkModeEnabled = value);
            await _runAction(actions.setDarkMode(widget.deviceId, value));
          },
        ),
        const SizedBox(height: 14),
        _SliderSettingRow(
          label: context.l10n.t('fontScaleLabel'),
          value: fontIndex,
          max: (_fontScaleValues.length - 1).toDouble(),
          divisions: _fontScaleValues.length - 1,
          valueText: _fontScaleValues[fontIndex.round()].toStringAsFixed(2),
          onChanged: (value) => setState(() => _fontScaleIndex = value),
          onChangeEnd: (value) async {
            final target = _fontScaleValues[value.round()];
            await _runAction(actions.setFontScale(widget.deviceId, target));
            if (mounted) {
              setState(() => _fontScaleIndex = null);
            }
          },
        ),
        const SizedBox(height: 16),
        _SliderSettingRow(
          label: context.l10n.t('displaySizeQuickLabel'),
          value: densityIndex,
          max: (_densityValues.length - 1).toDouble(),
          divisions: _densityValues.length - 1,
          valueText: '${_densityValues[densityIndex.round()]} dpi',
          onChanged: (value) => setState(() => _densityIndex = value),
          onChangeEnd: (value) async {
            final target = _densityValues[value.round()];
            await _runAction(
              actions.setDisplayDensity(widget.deviceId, target),
            );
            if (mounted) {
              setState(() => _densityIndex = null);
            }
          },
          trailing: IconButton(
            tooltip: context.l10n.t('displayDensityReset'),
            onPressed: () =>
                _runAction(actions.resetDisplayDensity(widget.deviceId)),
            icon: const Icon(CupertinoIcons.refresh, size: 18),
          ),
        ),
        const SizedBox(height: 14),
        _SwitchSettingRow(
          label: context.l10n.t('layoutBoundsToggle'),
          value: overview.layoutBoundsEnabled,
          onChanged: (value) =>
              _runAction(actions.toggleLayoutBounds(widget.deviceId, value)),
        ),
        const SizedBox(height: 10),
        _SwitchSettingRow(
          label: context.l10n.t('showTouchesToggle'),
          value: overview.showTouchesEnabled,
          onChanged: (value) =>
              _runAction(actions.setShowTouches(widget.deviceId, value)),
        ),
        const SizedBox(height: 10),
        _SwitchSettingRow(
          label: context.l10n.t('pointerLocationToggle'),
          value: overview.pointerLocationEnabled,
          onChanged: (value) =>
              _runAction(actions.setPointerLocation(widget.deviceId, value)),
        ),
        const SizedBox(height: 10),
        _SwitchSettingRow(
          label: context.l10n.t('demoModeToggle'),
          value: overview.demoModeEnabled,
          onChanged: (value) =>
              _runAction(actions.setDemoMode(widget.deviceId, value)),
        ),
      ],
    );
  }
}

class _ShortcutSettingAction {
  const _ShortcutSettingAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

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
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => DeviceSettingsPopup(deviceId: deviceId),
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

class _SwitchSettingRow extends StatelessWidget {
  const _SwitchSettingRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _SettingLabel(label)),
        Switch(value: value, onChanged: onChanged),
      ],
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
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
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ) ??
          const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
    );
  }
}
