import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ios/ios_mirror_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../../features/ios/widgets/ios_control_bar.dart';
import '../../l10n/app_localizations.dart';
import '../../settings/app_settings_controller.dart';
import '../../widget/app_toast.dart';
import 'mirror_toolbar_button.dart';

/// iOS 投屏工具栏：deviceId 路由 WDA，两个截图回调复用窗口的复制/保存流程。
/// 示例：由 MirrorFloatingToolbar 在 iOS 分支传入当前设备与截图回调。
/// 仅显示已接入的能力，截图独立于 WDA，音量不附加 Android 长按行为。
class IosMirrorToolbar extends ConsumerStatefulWidget {
  const IosMirrorToolbar({
    super.key,
    required this.deviceId,
    required this.onScreenshot,
    required this.onSaveScreenshot,
    this.isAirplay = false,
    this.airplayHandle,
  });

  final String deviceId;
  final VoidCallback onScreenshot;
  final VoidCallback onSaveScreenshot;
  final bool isAirplay;
  final int? airplayHandle;

  @override
  ConsumerState<IosMirrorToolbar> createState() => _IosMirrorToolbarState();
}

class _IosMirrorToolbarState extends ConsumerState<IosMirrorToolbar> {
  bool _showingError = false;
  bool _recording = false;
  bool _recordBusy = false;
  int? _recordingAirplayHandle;
  String? _recordingDeviceId;
  static const _airplayChannel = MethodChannel('anydeck/rust_texture');

  @override
  void didUpdateWidget(covariant IosMirrorToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_recording && (oldWidget.isAirplay != widget.isAirplay ||
        oldWidget.airplayHandle != widget.airplayHandle ||
        oldWidget.deviceId != widget.deviceId)) {
      _stopRecording();
    }
  }

  @override
  void dispose() {
    if (_recording && !_recordBusy) {
      if (_recordingAirplayHandle case final handle?) {
        _airplayChannel.invokeMethod<String>('stopRecording', {
          'handle': handle,
        }).ignore();
      } else {
        ref.read(iosDeviceServiceProvider).usbMirror
            .stopRecording(_recordingDeviceId ?? widget.deviceId).ignore();
      }
    }
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_recordBusy) return;
    if (_recording) {
      await _stopRecording();
      return;
    }
    setState(() => _recordBusy = true);
    final deviceId = widget.deviceId;
    final airplayHandle = widget.isAirplay ? widget.airplayHandle : null;
    final usbMirror = ref.read(iosDeviceServiceProvider).usbMirror;
    try {
      final settings = ref.read(appSettingsProvider);
      final path = ref.read(hostPlatformServiceProvider)
          .generateRecordPath(settings.screenshotSavePath, deviceId)
          .replaceFirst(RegExp(r'\.mp4$'), '.mov');
      if (widget.isAirplay) {
        final handle = airplayHandle;
        if (handle == null) throw StateError('airplayRecordingUnavailable');
        await _airplayChannel.invokeMethod<void>('startRecording', {
          'handle': handle,
          'path': path,
        });
        _recordingAirplayHandle = handle;
      } else {
        await usbMirror.startRecording(deviceId, path);
        _recordingAirplayHandle = null;
      }
      _recordingDeviceId = deviceId;
      if (mounted && widget.deviceId == deviceId &&
          widget.isAirplay == (airplayHandle != null) &&
          widget.airplayHandle == airplayHandle) {
        setState(() => _recording = true);
      } else if (airplayHandle != null) {
        _airplayChannel.invokeMethod<String>('stopRecording', {
          'handle': airplayHandle,
        }).ignore();
        _recordingAirplayHandle = null;
        _recordingDeviceId = null;
      } else {
        usbMirror.stopRecording(deviceId).ignore();
        _recordingDeviceId = null;
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(context,
            context.l10n.t('recordFailed').replaceAll('{error}', '$error'),
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _recordBusy = false);
    }
  }

  Future<void> _stopRecording() async {
    if (_recordBusy || !_recording) return;
    setState(() => _recordBusy = true);
    try {
      final handle = _recordingAirplayHandle;
      final path = handle != null
          ? await _airplayChannel.invokeMethod<String>('stopRecording', {
              'handle': handle,
            })
          : await ref.read(iosDeviceServiceProvider).usbMirror
              .stopRecording(_recordingDeviceId ?? widget.deviceId);
      if (path == null || path.isEmpty) {
        throw StateError('iosRecordingFileUnavailable');
      }
      if (mounted) {
        AppToast.show(context,
            context.l10n.t('recordSuccess').replaceAll('{path}', path));
      }
    } catch (error) {
      if (mounted) {
        AppToast.show(context,
            context.l10n.t('recordFailed').replaceAll('{error}', '$error'),
            isError: true);
      }
    } finally {
      _recordingAirplayHandle = null;
      _recordingDeviceId = null;
      if (mounted) setState(() { _recording = false; _recordBusy = false; });
    }
  }

  Future<void> _showError(String error) async {
    if (_showingError || !mounted || error.isEmpty) return;
    _showingError = true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.t('error')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
          child: SingleChildScrollView(
            child: SelectableText(iosControlErrorText(dialogContext, error)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.l10n.t('close')),
          ),
        ],
      ),
    );
    _showingError = false;
  }

  @override
  Widget build(BuildContext context) {
    final control = ref.watch(
      iosControlProvider(
        widget.deviceId,
      ).select((state) => (ready: state.ready, busy: state.busy)),
    );
    ref.listen<String?>(
      iosControlProvider(widget.deviceId).select((state) => state.error),
      (_, error) => _showError(error ?? ''),
    );
    ref.listen<String>(
      iosUsbFrameProvider(
        widget.deviceId,
      ).select((data) => '${data['error'] ?? ''}'),
      (_, error) => _showError(error),
    );
    final canControl = control.ready && !control.busy;
    void perform(String action, [Map<String, dynamic> args = const {}]) {
      ref
          .read(iosControlProvider(widget.deviceId).notifier)
          .perform(action, args);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Column(
          mainAxisSize: MainAxisSize.min,
        children: [
                  MirrorToolbarButton(
                    icon: const Icon(CupertinoIcons.lock),
                    tooltip: context.l10n.t('iosLock'),
                    onPressed: canControl ? () => perform('lock') : null,
                  ),
                  for (final button in [
                    (CupertinoIcons.volume_up, 'volumeUp'),
                    (CupertinoIcons.volume_down, 'volumeDown'),
                    (Icons.radio_button_unchecked, 'home'),
                  ])
                    MirrorToolbarButton(
                      icon: Icon(button.$1),
                      tooltip: context.l10n.t(button.$2),
                      onPressed: canControl
                          ? () => perform('button', {'name': button.$2})
                          : null,
                    ),
                  MirrorToolbarButton(
                    icon: const Icon(Icons.text_fields),
                    tooltip: context.l10n.t('getClipboardInput'),
                    onPressed: canControl
                        ? () async {
                            final data = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            if (!context.mounted) return;
                            final text = data?.text;
                            if (text == null || text.isEmpty) {
                              AppToast.show(
                                context,
                                context.l10n.t('clipboardEmpty'),
                                type: AppToastType.warning,
                              );
                              return;
                            }
                            perform('text', {'text': text});
                          }
                        : null,
                  ),
                  MirrorToolbarButton(
                    icon: const Icon(CupertinoIcons.camera),
                    tooltip: context.l10n.t('screenshotTooltip'),
                    onPressed: widget.onScreenshot,
                    onLongPress: widget.onSaveScreenshot,
                  ),
                  MirrorToolbarButton(
                    key: const ValueKey('ios-usb-record-toggle'),
                    icon: Icon(_recording ? CupertinoIcons.stop_fill
                        : CupertinoIcons.videocam),
                    tooltip: context.l10n.t(_recording ? 'stopRecord'
                        : widget.isAirplay ? 'iosAirplayRecord' : 'iosUsbRecord'),
                    onPressed: _recordBusy ||
                            (widget.isAirplay
                                ? widget.airplayHandle == null
                                : ref.watch(activeIosMirrorProvider(widget.deviceId)) == null)
                        ? null : _toggleRecording,
                  ),
                  const SizedBox(width: 6),
                  MirrorToolbarButton(
                    key: const ValueKey('ios-control-toggle'),
                    onPressed: () => perform(
                      control.ready || control.busy ? 'stop' : 'start',
                    ),
                    icon: control.busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            control.ready
                                ? Icons.mouse
                                : Icons.touch_app_outlined,
                            size: 16,
                          ),
                    tooltip: context.l10n.t(
                      control.busy
                          ? 'iosCancelControl'
                          : control.ready
                          ? 'iosStopControl'
                          : 'iosStartControl',
                    ),
                  ),
        ],
        ),
      ),
    );
  }
}
