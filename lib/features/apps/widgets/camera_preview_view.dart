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
    final concurrentAsync =
        ref.watch(concurrentCameraSupportedProvider(deviceId));
    final concurrentSupported = concurrentAsync.value ?? false;
    final colors = Theme.of(context).colorScheme;
    final effectiveMode =
        (!concurrentSupported && state.mode == CameraPreviewMode.dual)
            ? CameraPreviewMode.back
            : state.mode;

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
                      DropdownButton<CameraPreviewMode>(
                        value: effectiveMode,
                        items: [
                          DropdownMenuItem(
                            value: CameraPreviewMode.back,
                            child: Text(context.l10n.t('cameraBack')),
                          ),
                          DropdownMenuItem(
                            value: CameraPreviewMode.front,
                            child: Text(context.l10n.t('cameraFront')),
                          ),
                          if (concurrentSupported)
                            DropdownMenuItem(
                              value: CameraPreviewMode.dual,
                              child: Text(context.l10n.t('cameraDual')),
                            ),
                        ],
                        onChanged: state.busy || state.isStreaming
                            ? null
                            : (value) {
                                if (value != null) {
                                  controller.selectMode(value);
                                }
                              },
                      ),
                      FilledButton.icon(
                        onPressed:
                            online &&
                                    compatible &&
                                    !state.busy &&
                                    !state.isStreaming
                                ? controller.start
                                : null,
                        icon: const Icon(Icons.videocam_outlined),
                        label: Text(context.l10n.t('cameraStart')),
                      ),
                      OutlinedButton(
                        onPressed: state.isStreaming || state.busy
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
            child: effectiveMode == CameraPreviewMode.dual
                ? _buildDualPreview(context, colors, state)
                : _buildSinglePreview(context, colors, state),
          ),
        ],
      ),
    );
  }

  /// 单摄像头画面渲染
  Widget _buildSinglePreview(
    BuildContext context,
    ColorScheme colors,
    CameraPreviewState state,
  ) {
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: state.textureId != null && state.width > 0 && state.height > 0
          ? Center(
              child: AspectRatio(
                aspectRatio: state.width / state.height,
                child: Texture(textureId: state.textureId!),
              ),
            )
          : Center(child: Text(context.l10n.t('cameraIdle'))),
    );
  }

  /// 前后双摄像头并排渲染画面
  Widget _buildDualPreview(
    BuildContext context,
    ColorScheme colors,
    CameraPreviewState state,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _buildCameraBox(
            context,
            colors,
            label: context.l10n.t('cameraBack'),
            textureId: state.textureId,
            width: state.width,
            height: state.height,
            busy: state.busy,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildCameraBox(
            context,
            colors,
            label: context.l10n.t('cameraFront'),
            textureId: state.frontTextureId,
            width: state.frontWidth,
            height: state.frontHeight,
            busy: state.busy,
          ),
        ),
      ],
    );
  }

  /// 单个镜头的预览框与标签包装
  Widget _buildCameraBox(
    BuildContext context,
    ColorScheme colors, {
    required String label,
    required int? textureId,
    required int width,
    required int height,
    required bool busy,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: textureId != null && width > 0 && height > 0
                ? Center(
                    child: AspectRatio(
                      aspectRatio: width / height,
                      child: Texture(textureId: textureId),
                    ),
                  )
                : Center(
                    child: Text(
                      busy
                          ? context.l10n.t('cameraWaitingFrame')
                          : context.l10n.t('cameraIdle'),
                      textAlign: TextAlign.center,
                    ),
                  ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
