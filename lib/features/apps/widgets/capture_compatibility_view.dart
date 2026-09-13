import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/scrcpy/device_capture_compatibility.dart';

/// 展示功能门槛及当前设备判断；kind 为 camera、microphone 或 clipboard。
/// 用法：CaptureCompatibilityView(deviceId: serial, kind: 'microphone')。
class CaptureCompatibilityView extends ConsumerWidget {
  const CaptureCompatibilityView({
    super.key,
    required this.deviceId,
    required this.kind,
  });
  final String deviceId;
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sdk = ref.watch(captureSdkProvider(deviceId));
    final host = ref.watch(captureHostSupportedProvider);
    final minimum = kind == 'camera'
        ? 31
        : kind == 'microphone'
        ? 30
        : 21;
    final value = sdk.value;
    final status = !host
        ? 'captureHostUnsupported'
        : sdk.isLoading
        ? 'captureChecking'
        : value == null
        ? 'captureUnknown'
        : value < minimum
        ? 'captureUnsupported'
        : 'captureSupported';
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        '${context.l10n.t('${kind}Compatibility')}\n'
        '${context.l10n.t('captureCurrent')}: ${value == null ? '—' : 'API $value'} · ${context.l10n.t(status)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: !host || (value != null && value < minimum)
              ? colors.error
              : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
