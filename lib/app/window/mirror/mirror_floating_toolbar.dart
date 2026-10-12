import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/scrcpy/embedded_scrcpy_service.dart';

import '../../../core/device_actions/device_action_service.dart';
import '../../../core/scrcpy/screen_record_provider.dart';
import '../../../core/scrcpy/scrcpy_keycode_helper.dart';
import '../../../core/providers/app_providers.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widget/app_toast.dart';
import '../../settings/app_settings_controller.dart';
import '../../../features/control/device_settings_popup.dart';
import '../../../features/widgets/device_power_actions.dart';
import 'mirror_back_long_press_handler.dart';
import 'mirror_toolbar_button.dart';
import 'ios_mirror_toolbar.dart';
import 'mirror_volume_long_press_handler.dart';
import 'mirror_window_controller.dart';
import '../../../core/ios/ios_mirror_service.dart';
import '../../../features/control/recorder/widgets/mirror_mouse_recorder_button.dart';
import 'mirror_screen_recording_action.dart';

export 'mirror_toolbar_button.dart';

///投屏窗口中工具栏
class MirrorFloatingToolbar extends ConsumerStatefulWidget {
  const MirrorFloatingToolbar({
    super.key,
    required this.deviceId,
    required this.windowId,
    required this.controller,
  });

  final String deviceId;
  final String windowId;
  final MirrorWindowController controller;

  @override
  ConsumerState<MirrorFloatingToolbar> createState() =>
      _MirrorFloatingToolbarState();
}

class _MirrorFloatingToolbarState extends ConsumerState<MirrorFloatingToolbar> {
  late final MirrorBackLongPressHandler _backLongPressHandler;
  late final MirrorVolumeLongPressHandler _volumeLongPressHandler;


  @override
  void initState() {
    super.initState();
    _backLongPressHandler = MirrorBackLongPressHandler(
      ref: ref,
      deviceId: widget.deviceId,
      displayNameResolver: widget.controller.foregroundAppNameWithIcon,
      onForceStopSuccess: widget.controller.clearForegroundAppIfMatches,
    );
    _volumeLongPressHandler = MirrorVolumeLongPressHandler(
      ref: ref,
      deviceId: widget.deviceId,
    );
  }



  @override
  void dispose() {
    _backLongPressHandler.cancel();
    _volumeLongPressHandler.cancel();
    super.dispose();
  }



  Future<void> _takeScreenshot(BuildContext context, String deviceId, {required bool saveToFile}) async {
    try {
      final bytes = widget.controller.isIos
          ? await ref.read(iosCommandServiceProvider).captureScreenshot(deviceId)
          : (widget.controller.isHarmony
              ? await ref.read(hdcServiceProvider).captureScreenshot(deviceId)
              : await ref.read(adbServiceProvider).captureScreenshot(deviceId));

      final hostPlatform = ref.read(hostPlatformServiceProvider);

      // 复制到剪切板
      final copied = await hostPlatform.copyImageToClipboard(bytes);

      if (saveToFile) {
        final settings = ref.read(appSettingsProvider);
        final savePath = hostPlatform.generateScreenshotPath(
          settings.screenshotSavePath,
          deviceId,
        );
        final file = File(savePath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);

        if (context.mounted) {
          AppToast.show(
            context,
            '${context.l10n.t('saveSuccess')}: $savePath${copied ? " (已复制到剪贴板)" : ""}',
          );
        }
      } else {
        if (context.mounted) {
          if (copied) {
            AppToast.show(context, context.l10n.t('copySuccess'));
          } else {
            AppToast.show(
              context,
              context.l10n.locale.languageCode == 'zh'
                  ? '复制至剪贴板失败'
                  : 'Failed to copy to clipboard',
              isError: true,
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.show(context, '${context.l10n.t('error')}: $e', isError: true);
      }
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // iOS 只创建已接入的操作，不订阅 Android 录屏和屏幕电源状态。
    if (widget.controller.isIos) {
      return IosMirrorToolbar(
        deviceId: widget.deviceId,
        onScreenshot: () => _takeScreenshot(context, widget.deviceId, saveToFile: false),
        onSaveScreenshot: () => _takeScreenshot(context, widget.deviceId, saveToFile: true),
      );
    }
    final actions = ref.read(deviceActionServiceProvider);
    final isScreenOff = ref.watch(screenPowerOffProvider(widget.deviceId));
    final recordState = ref.watch(screenRecordProvider(widget.deviceId));

    return _buildExpandedToolbar(
      context,
      actions,
      isDark,
      isScreenOff,
      recordState,
    );
  }

  Widget _buildExpandedToolbar(
    BuildContext context,
    DeviceActionService actions,
    bool isDark,
    bool isScreenOff,
    ScreenRecordState recordState,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // 吸收点击事件，防止穿透
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Group 1: 电源, 设备屏幕
            MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.power,
                color: Theme.of(context).appColors.toolbarForeground,
              ),
              tooltip: context.l10n.t('power'),
              onPressed: () {
                pressPowerKeyAndResetScreenPower(
                  actions: actions,
                  deviceId: widget.deviceId,
                  screenPowerOffNotifier: ref.read(
                    screenPowerOffProvider(widget.deviceId).notifier,
                  ),
                );
              },
            ),
            if (!widget.controller.isIos && !widget.controller.isHarmony)
              MirrorToolbarButton(
                icon: Icon(
                  isScreenOff ? Icons.mobile_off : Icons.smartphone,
                  color: isScreenOff
                      ? Colors.orange
                      : (Theme.of(context).appColors.toolbarForeground),
                ),
                tooltip: context.l10n.t('screenPowerToggle'),
                onPressed: () {
                  ref
                      .read(screenPowerOffProvider(widget.deviceId).notifier)
                      .toggleScreenPower(!isScreenOff);
                },
              ),
            const MirrorToolbarDivider(),

            // Group 2: 音量+, 音量-
            MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.volume_up,
                color: Theme.of(context).appColors.toolbarForeground,
              ),
              tooltip: context.l10n.t('volumeUp'),
              onPressed: () {
                if (_volumeLongPressHandler.shouldSuppressVolumeUp) {
                  return;
                }
                actions.volumeUp(widget.deviceId);
              },
              onPointerDown: () =>
                  _volumeLongPressHandler.handleVolumeUpPointerDown(context),
              onPointerUp: _volumeLongPressHandler.handleVolumeUpPointerUp,
              onPointerCancel: _volumeLongPressHandler.handleVolumeUpPointerUp,
            ),
            MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.volume_down,
                color: Theme.of(context).appColors.toolbarForeground,
              ),
              tooltip: context.l10n.t('volumeDown'),
              onPressed: () {
                if (_volumeLongPressHandler.shouldSuppressVolumeDown) {
                  return;
                }
                actions.volumeDown(widget.deviceId);
              },
              onPointerDown: () =>
                  _volumeLongPressHandler.handleVolumeDownPointerDown(context),
              onPointerUp: _volumeLongPressHandler.handleVolumeDownPointerUp,
              onPointerCancel:
                  _volumeLongPressHandler.handleVolumeDownPointerUp,
            ),
            const MirrorToolbarDivider(),

            // Group 3: 后退, 主屏, 菜单
            if (!widget.controller.isIos)
              MirrorToolbarButton(
                icon: Icon(
                  Icons.chevron_left,
                  size: 18,
                  color: Theme.of(context).appColors.toolbarForeground,
                ),
                tooltip: context.l10n.t('back'),
                onPressed: () {
                  if (_backLongPressHandler.shouldSuppressBack) {
                    return;
                  }
                  actions.keyEvent(widget.deviceId, 4);
                },
                onPointerDown: () =>
                    _backLongPressHandler.handlePointerDown(context),
                onPointerUp: _backLongPressHandler.handlePointerUp,
                onPointerCancel: _backLongPressHandler.handlePointerUp,
              ),
            MirrorToolbarButton(
              icon: Icon(
                Icons.radio_button_unchecked,
                color: Theme.of(context).appColors.toolbarForeground,
              ),
              tooltip: context.l10n.t('home'),
              onPressed: () {
                actions.keyEvent(widget.deviceId, 3);
              },
            ),
            if (!widget.controller.isIos)
              MirrorToolbarButton(
                icon: Icon(
                  Icons.crop_square,
                  color: Theme.of(context).appColors.toolbarForeground,
                ),
                tooltip: context.l10n.t('menuKey'),
                onPressed: () => actions.keyEvent(widget.deviceId, 187),
              ),
            // const _VerticalDivider(),
            // Group 4: 通知栏, T
            // MirrorToolbarButton(
            //   icon: Icon(
            //     CupertinoIcons.bell,
            //     color: Theme.of(context).appColors.toolbarForeground,
            //   ),
            //   tooltip: context.l10n.t('notificationBar'),
            //   onPressed: () => actions.openNotificationBar(widget.deviceId),
            // ),
            MirrorToolbarButton(
              icon: Text(
                'T',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).appColors.toolbarForeground,
                ),
              ),
              tooltip: context.l10n.t('getClipboardInput'),
              onPressed: () async {
                final clipboardData = await Clipboard.getData(
                  Clipboard.kTextPlain,
                );
                if (clipboardData != null &&
                    clipboardData.text != null &&
                    clipboardData.text!.isNotEmpty) {
                  final text = clipboardData.text!;
                  final success = widget.controller.isIos
                      ? await ref.read(iosControlProvider(widget.deviceId).notifier).perform('text', {'text': text})
                      : (widget.controller.isHarmony
                          ? (await ref
                                    .read(hdcServiceProvider)
                                    .inputText(widget.deviceId, text))
                                .isSuccess
                          : await ref
                                  .read(embeddedScrcpyServiceProvider)
                                  .sendControl(
                                    deviceId: widget.deviceId,
                                    controlMessage:
                                        ScrcpyKeycodeHelper.serializeTextEvent(text),
                                  ));
                  if (!success && context.mounted) {
                    AppToast.show(
                      context,
                      context.l10n.t('sendClipboardFailed'),
                      isError: true,
                    );
                  }
                } else {
                  if (context.mounted) {
                    AppToast.show(
                      context,
                      context.l10n.t('clipboardEmpty'),
                      type: AppToastType.warning,
                    );
                  }
                }
              },
            ),
            const MirrorToolbarDivider(),

            // Group 5: 截图, 录屏, 前台窗口
            MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.scope,
                color: Theme.of(context).appColors.toolbarForeground,
              ),
              tooltip: context.l10n.t('focus'),
              onPressed: () async {
                if (!widget.controller.isHarmony) {
                  // Android 设备同步刷新标题栏的前台应用 icon。
                  widget.controller.identifyForegroundApp();
                }

                final res = widget.controller.isHarmony
                    ? await ref
                          .read(hdcServiceProvider)
                          .currentFocus(widget.deviceId)
                    : await actions.currentFocus(widget.deviceId);
                if (context.mounted) {
                  showDialog<void>(
                    context: context,
                    builder: (context) {
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      final cardColor = isDark
                          ? const Color(0xff1e1e1e)
                          : const Color(0xffffffff);
                      return AlertDialog(
                        backgroundColor: cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        contentPadding: const EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          16,
                        ),
                        actionsPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          12,
                        ),
                        title: Row(
                          children: [
                            Icon(
                              CupertinoIcons.scope,
                              color: Theme.of(context).appColors.toolbarForeground,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              context.l10n.t('currentFocusWindow'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        content: SelectableText(
                          res.stdout,
                          style: const TextStyle(fontSize: 13),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              context.l10n.t('ok'),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                }
              },
            ),
            MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.camera,
                color: Theme.of(context).appColors.toolbarForeground,
              ),
              tooltip: context.l10n.t('screenshotTooltip'),
              onPressed: () => _takeScreenshot(
                context,
                widget.deviceId,
                saveToFile: false,
              ),
              onLongPress: () => _takeScreenshot(
                context,
                widget.deviceId,
                saveToFile: true,
              ),
            ),
            MirrorToolbarButton(
              icon: Icon(
                recordState.isRecording
                    ? CupertinoIcons.stop
                    : CupertinoIcons.videocam,
                size: 22,
                color: recordState.isRecording
                    ? Colors.red
                    : (Theme.of(context).appColors.toolbarForeground),
              ),
              tooltip: recordState.isRecording
                  ? context.l10n.t('stopRecord')
                  : context.l10n.t('startRecord'),
              isLoading: recordState.isStopping,
              badge: recordState.isRecording
                  ? const MirrorPulsingRecordBadge()
                  : null,
              onPressed: () => toggleMirrorScreenRecording(context, ref, widget.deviceId),
            ),
            if (recordState.isRecording) ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 8),
                child: Text(
                  _formatDuration(recordState.durationSeconds),
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            MirrorMouseRecorderButton(
              deviceId: widget.deviceId,
              isDark: isDark,
            ),

            MirrorToolbarButton(
              icon: DeviceSettingsIcon(
                color: Theme.of(context).appColors.toolbarForeground,
                size: 18,
              ),
              tooltip: context.l10n.t('deviceSettings'),
              onPressed: () => showDeviceSettingsPopup(
                context: context,
                deviceId: widget.deviceId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
