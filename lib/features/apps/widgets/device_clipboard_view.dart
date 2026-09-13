import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/device_capture_compatibility.dart';
import '../controller/device_auxiliary_controller.dart';
import 'capture_compatibility_view.dart';

/// 手机文本剪贴板实时面板；仅读取，复制到电脑需用户点击。
/// deviceId 为 ADB serial，离开页面清空内存文本并停止独立连接。
class DeviceClipboardView extends ConsumerWidget {
  const DeviceClipboardView({super.key, required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (deviceId: deviceId, microphone: false);
    final state = ref.watch(deviceAuxiliaryProvider(key));
    final controller = ref.read(deviceAuxiliaryProvider(key).notifier);
    final sdk = ref.watch(captureSdkProvider(deviceId)).value;
    final online = ref.watch(deviceOnlineProvider(deviceId));
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(context.l10n.t('clipboardIntro')),
        CaptureCompatibilityView(deviceId: deviceId, kind: 'clipboard'),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilledButton.icon(
              onPressed:
                  online && ref.watch(captureHostSupportedProvider) && (sdk ?? 0) >= 21 && !state.busy && !state.active
                  ? controller.start
                  : null,
              icon: const Icon(Icons.content_paste_search),
              label: Text(context.l10n.t('clipboardStart')),
            ),
            OutlinedButton(
              onPressed:
                  (state.active || state.busy) &&
                      state.messageKey != 'auxStopping'
                  ? () => controller.stop()
                  : null,
              child: Text(context.l10n.t('clipboardStop')),
            ),
            TextButton(
              onPressed: state.active && !state.busy
                  ? controller.refresh
                  : null,
              child: Text(context.l10n.t('clipboardRefresh')),
            ),
            TextButton(
              onPressed: state.text == null
                  ? null
                  : () async {
                      try {
                        await Clipboard.setData(
                          ClipboardData(text: state.text!),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            SnackBar(
                              content: Text(context.l10n.t('clipboardCopied')),
                            ),
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            SnackBar(
                              content: Text(
                                context.l10n.t('clipboardCopyFailed'),
                              ),
                            ),
                          );
                        }
                      }
                    },
              child: Text(context.l10n.t('clipboardCopy')),
            ),
          ],
        ),
        if (state.busy) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            context.l10n.t(state.messageKey),
            style: TextStyle(
              color: state.failed ? colors.error : colors.onSurfaceVariant,
            ),
          ),
        ),
        if (state.receivedAt != null)
          Text(
            '${context.l10n.t('clipboardReceived')}: ${state.receivedAt!.toLocal().toString().split('.').first}',
          ),
        Expanded(
          child: ColoredBox(
            color: colors.surfaceContainerHighest,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                state.text ?? context.l10n.t('clipboardEmptyNote'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
