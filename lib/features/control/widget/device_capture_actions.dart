part of '../../dashboard_screen.dart';

/// 构建设备操作区的锁屏、截图和录屏按钮。
List<Widget> buildDeviceCaptureActions(
  BuildContext context,
  WidgetRef ref,
  DiscoveredDevice device,
) {
  return [
    _ActionButton(
      icon: CupertinoIcons.lock,
      label: context.l10n.t('lockScreen'),
      onPressed: () => _runAdbAction(
        context,
        ref,
        ref.read(deviceActionServiceProvider).lockScreen(device.id),
      ),
    ),
    _ActionButton(
      icon: CupertinoIcons.camera,
      label: context.l10n.t('screenshot'),
      onPressed: () => _captureAndSaveDeviceScreenshot(context, ref, device),
    ),
    _DeviceScreenRecordButton(deviceId: device.id),
  ];
}

Future<void> _captureAndSaveDeviceScreenshot(
  BuildContext context,
  WidgetRef ref,
  DiscoveredDevice device,
) async {
  try {
    // 在设备请求前获取宿主依赖，列表切换或组件销毁后仍能完成本地保存。
    final host = ref.read(hostPlatformServiceProvider);
    final settings = ref.read(appSettingsProvider);
    final bytes = device.isIos
        ? await ref.read(iosCommandServiceProvider).captureScreenshot(device.id)
        : device.isHarmony
        ? await ref.read(hdcServiceProvider).captureScreenshot(device.id)
        : await ref.read(adbServiceProvider).captureScreenshot(device.id);
    final savePath = host.generateScreenshotPath(
      settings.screenshotSavePath,
      device.id,
    );
    final file = File(savePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    final copied = await host.copyImageToClipboard(bytes);
    if (context.mounted) {
      AppToast.show(
        context,
        '${context.l10n.t('saveSuccess')}: $savePath${copied ? " (${context.l10n.t('copySuccess')})" : ""}',
      );
    }
  } catch (error) {
    if (context.mounted) {
      AppToast.show(
        context,
        '${context.l10n.t('error')}: $error',
        isError: true,
      );
    }
  }
}

/// 录屏按钮订阅设备级录屏状态，录制期间显示时长并切换为停止操作。
class _DeviceScreenRecordButton extends ConsumerWidget {
  const _DeviceScreenRecordButton({required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(screenRecordProvider(deviceId));
    final minutes = (state.durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (state.durationSeconds % 60).toString().padLeft(2, '0');
    final label = state.isRecording
        ? '${context.l10n.t('screenRecord')} $minutes:$seconds'
        : context.l10n.t('screenRecord');

    if (state.isRecording) {
      return FilledButton.icon(
        icon: state.isStopping
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(CupertinoIcons.stop_circle_fill, size: 18),
        label: Text(label),
        onPressed: state.isStopping
            ? null
            : () => toggleMirrorScreenRecording(context, ref, deviceId),
      );
    }
    return OutlinedButton.icon(
      icon: const Icon(CupertinoIcons.recordingtape, size: 18),
      label: Text(label),
      onPressed: () => toggleMirrorScreenRecording(context, ref, deviceId),
    );
  }
}
