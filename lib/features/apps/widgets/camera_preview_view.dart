import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';
import '../controller/camera_preview_controller.dart';
import '../../../core/scrcpy/device_capture_compatibility.dart';
import 'capture_compatibility_view.dart';
import 'microphone_controls.dart';

/// 页面内摄像头预览，deviceId 为 ADB 路由；画面由 Rust 解码并通过薄 Swift Texture 桥接显示。
/// 仅显式点击开始才打开摄像头，移除此组件后自动释放其 Provider 会话。
class CameraPreviewView extends ConsumerWidget {
  const CameraPreviewView({super.key, required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cameraPreviewProvider(deviceId));
    final controller = ref.read(cameraPreviewProvider(deviceId).notifier);
    final online = ref.watch(deviceOnlineProvider(deviceId));
    final sdk = ref.watch(captureSdkProvider(deviceId)).value;
    final compatible =
        ref.watch(captureHostSupportedProvider) && (sdk ?? 0) >= 31;
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight * 0.65,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Text(context.l10n.t('cameraIntro')),
                  CaptureCompatibilityView(deviceId: deviceId, kind: 'camera'),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DropdownButton<bool>(
                        value: state.front,
                        items: [
                          DropdownMenuItem(
                            value: false,
                            child: Text(context.l10n.t('cameraBack')),
                          ),
                          DropdownMenuItem(
                            value: true,
                            child: Text(context.l10n.t('cameraFront')),
                          ),
                        ],
                        onChanged: state.busy || state.textureId != null
                            ? null
                            : (value) {
                                if (value != null) {
                                  controller.selectFront(value);
                                }
                              },
                      ),
                      FilledButton.icon(
                        onPressed:
                            online &&
                                compatible &&
                                !state.busy &&
                                state.textureId == null
                            ? controller.start
                            : null,
                        icon: const Icon(Icons.videocam_outlined),
                        label: Text(context.l10n.t('cameraStart')),
                      ),
                      OutlinedButton(
                        onPressed: state.textureId != null || state.busy
                            ? () => controller.stop()
                            : null,
                        child: Text(context.l10n.t('cameraStop')),
                      ),
                    ],
                  ),
                  if (state.busy) const LinearProgressIndicator(),
                  if (state.messageKey != null)
                    Text(context.l10n.t(state.messageKey!)),
                  MicrophoneControls(deviceId: deviceId),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ColoredBox(
              color: colors.surfaceContainerHighest,
              child:
                  state.textureId != null && state.width > 0 && state.height > 0
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: state.width / state.height,
                        child: Texture(textureId: state.textureId!),
                      ),
                    )
                  : Center(child: Text(context.l10n.t('cameraIdle'))),
            ),
          ),
        ],
      ),
    );
  }
}
