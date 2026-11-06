import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/scrcpy/device_capture_compatibility.dart';
import '../../../core/virtual_camera/virtual_camera_controller.dart';
import '../../apps/controller/camera_preview_controller.dart';

/// 摄像头弹窗中的系统摄像头入口。deviceId 指定本次提供给 Mac 的 Android 设备。
/// 只在明确开启后配置原生服务，退出弹窗保持会议供帧；停止按钮可随时撤销。
class VirtualCameraControls extends ConsumerStatefulWidget {
  const VirtualCameraControls({super.key, required this.deviceId});
  final String deviceId;

  @override
  ConsumerState<VirtualCameraControls> createState() =>
      _VirtualCameraControlsState();
}

class _VirtualCameraControlsState extends ConsumerState<VirtualCameraControls> {
  bool _front = false;

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(virtualCameraHostProvider)) return const SizedBox.shrink();
    final state = ref.watch(virtualCameraProvider);
    final controller = ref.read(virtualCameraProvider.notifier);
    final online = ref.watch(deviceOnlineProvider(widget.deviceId));
    final sdk = ref.watch(captureSdkProvider(widget.deviceId)).value;
    final ownsDevice = state.ownsDevice(widget.deviceId);
    final front = ownsDevice ? state.front : _front;
    final canEnable = state.ready && online && (sdk ?? 0) >= 31 && !state.busy;
    final l10n = context.l10n;

    Future<void> enable(bool facing) => controller.enable(
      deviceId: widget.deviceId,
      front: facing,
      stopPreview: () =>
          ref.read(cameraPreviewProvider(widget.deviceId).notifier).stop(),
      labels: {
        'title': 'AnyDeck Camera',
        'front': l10n.t('cameraFront'),
        'back': l10n.t('cameraBack'),
        'stop': l10n.t('virtualCameraStop'),
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Text(
          l10n.t('virtualCameraTitle'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(l10n.t('virtualCameraIntro')),
        Text(l10n.t(state.messageKey)),
        if (state.busy) const LinearProgressIndicator(),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!state.installed)
              OutlinedButton(
                onPressed: state.supported && !state.busy
                    ? controller.activate
                    : null,
                child: Text(l10n.t('virtualCameraInstall')),
              ),
            if (state.installed)
              TextButton(
                onPressed: state.busy ? null : controller.deactivate,
                child: Text(l10n.t('virtualCameraUninstall')),
              ),
            if (state.ready || ownsDevice)
              DropdownButton<bool>(
                key: const ValueKey('virtual-camera-lens'),
                value: front,
                items: [
                  DropdownMenuItem(
                    value: false,
                    child: Text(l10n.t('cameraBack')),
                  ),
                  DropdownMenuItem(
                    value: true,
                    child: Text(l10n.t('cameraFront')),
                  ),
                ],
                onChanged: !state.busy && (!ownsDevice || canEnable)
                    ? (value) {
                        if (value == null) return;
                        setState(() => _front = value);
                        if (ownsDevice) enable(value);
                      }
                    : null,
              ),
          ],
        ),
        SwitchListTile.adaptive(
          key: const ValueKey('virtual-camera-enable'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.t('virtualCameraEnable')),
          subtitle: Text(l10n.t('virtualCameraLifetime')),
          value: ownsDevice,
          onChanged: ownsDevice && !state.busy
              ? (_) => controller.disable()
              : canEnable
              ? (_) => enable(front)
              : null,
        ),
      ],
    );
  }
}
