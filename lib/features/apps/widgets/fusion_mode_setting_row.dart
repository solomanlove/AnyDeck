import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/widget/app_toast.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/fusion_mode_preference.dart';

/// 应用页的设备级融合投屏选择，默认值由 Android SDK 和显式偏好共同决定。
class FusionModeSettingRow extends ConsumerStatefulWidget {
  const FusionModeSettingRow({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<FusionModeSettingRow> createState() =>
      _FusionModeSettingRowState();
}

class _FusionModeSettingRowState extends ConsumerState<FusionModeSettingRow> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(deviceFusionModeProvider(widget.deviceId));
    final online = ref.watch(deviceOnlineProvider(widget.deviceId));
    final mode = status.asData?.value;
    final enabled = mode?.state == FusionModeState.enabled;
    final available = online && !_saving && mode?.canChange == true;
    final hintKey = !online
        ? 'fusionDeviceOffline'
        : status.isLoading
        ? 'fusionChecking'
        : status.hasError
        ? 'fusionDetectionUnavailable'
        : mode?.state == FusionModeState.unsupported
        ? 'fusionUnsupported'
        : mode?.state == FusionModeState.unknown
        ? 'fusionDetectionUnavailable'
        : 'fusionModeHint';

    return Container(
      key: const Key('fusionModeSettingRow'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.rectangle_on_rectangle, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.t('fusionModeTitle'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  context.l10n.t(hintKey),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            key: const Key('fusionModeSwitch'),
            value: enabled,
            onChanged: available
                ? (value) => _save(mode!.physicalDeviceKey!, value)
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _save(String physicalKey, bool enabled) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(fusionModePreferenceProvider)
          .setEnabled(physicalKey, enabled);
      ref.invalidate(deviceFusionModeProvider(widget.deviceId));
      // 设置只有主窗口可写；通知已有子窗口更新其本地状态。
      try {
        for (final window in await WindowController.getAll()) {
          try {
            await window.invokeMethod<void>('fusionModeChanged', physicalKey);
          } catch (_) {}
        }
      } catch (_) {}
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          context.l10n
              .t('fusionSaveFailed')
              .replaceAll('{error}', error.toString()),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
