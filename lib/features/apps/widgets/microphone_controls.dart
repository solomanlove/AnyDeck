import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/device_capture_compatibility.dart';
import '../controller/device_auxiliary_controller.dart';
import 'capture_compatibility_view.dart';

/// 摄像头页内的独立麦克风控制，不依赖摄像头是否正在预览。
/// deviceId 为目标 ADB serial，移除组件后释放音频采集和电脑播放器。
class MicrophoneControls extends ConsumerWidget {
  const MicrophoneControls({super.key, required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (deviceId: deviceId, microphone: true);
    final state = ref.watch(deviceAuxiliaryProvider(key));
    final controller = ref.read(deviceAuxiliaryProvider(key).notifier);
    final sdk = ref.watch(captureSdkProvider(deviceId)).value;
    final supported =
        ref.watch(captureHostSupportedProvider) && (sdk ?? 0) >= 30;
    final online = ref.watch(deviceOnlineProvider(deviceId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CaptureCompatibilityView(deviceId: deviceId, kind: 'microphone'),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonalIcon(
              onPressed: online && supported && !state.busy && !state.active
                  ? controller.start
                  : null,
              icon: const Icon(Icons.mic_outlined),
              label: Text(context.l10n.t('microphoneStart')),
            ),
            OutlinedButton(
              onPressed:
                  (state.active || state.busy) &&
                      state.messageKey != 'auxStopping'
                  ? () => controller.stop()
                  : null,
              child: Text(context.l10n.t('microphoneStop')),
            ),
            OutlinedButton.icon(
              onPressed: state.active && !state.busy
                  ? controller.toggleMute
                  : null,
              icon: Icon(
                state.muted
                    ? Icons.volume_off_outlined
                    : Icons.volume_up_outlined,
              ),
              label: Text(
                context.l10n.t(
                  state.muted ? 'microphoneUnmute' : 'microphoneMute',
                ),
              ),
            ),
            Text(
              context.l10n.t(state.messageKey),
              style: TextStyle(
                color: state.failed
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
          ],
        ),
        if (state.busy) const LinearProgressIndicator(),
      ],
    );
  }
}
