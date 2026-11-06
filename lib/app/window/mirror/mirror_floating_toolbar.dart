import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../core/device_actions/device_action_service.dart';
import '../../../core/harmony/harmony_foreground_window.dart';
import '../../../core/ios/ios_mirror_service.dart';
import 'mirror_foreground_window_label.dart';
import '../../../core/scrcpy/screen_record_provider.dart';
import '../../../core/providers/app_providers.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widget/app_toast.dart';
import '../../settings/app_settings_controller.dart';
import '../../../features/control/device_settings_popup.dart';
import '../../../features/widgets/device_power_actions.dart';
import 'mirror_back_long_press_handler.dart';
import 'mirror_toolbar_button.dart';
import 'harmony_power_button.dart';
import 'ios_mirror_toolbar.dart';
import 'mirror_volume_long_press_handler.dart';
import 'mirror_window_controller.dart';
import '../../../features/control/recorder/widgets/mirror_mouse_recorder_button.dart';
import 'mirror_screen_recording_action.dart';
import 'mirror_clipboard_input_button.dart';
import 'mirror_clipboard_button.dart';
import 'mirror_whiteboard_controls.dart';
import '../../../features/control/whiteboard/mirror_whiteboard_controller.dart';

export 'mirror_toolbar_button.dart';

part 'mirror_toolbar_actions.dart';

///投屏窗口中工具栏
class MirrorFloatingToolbar extends ConsumerStatefulWidget {
  const MirrorFloatingToolbar({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.windowId,
    required this.controller,
    this.isAirplay = false,
    this.airplayHandle,
    this.whiteboard,
  });

  final String deviceId;
  final String deviceName;
  final String windowId;
  final MirrorWindowController controller;
  final bool isAirplay;
  final int? airplayHandle;
  final MirrorWhiteboardController? whiteboard;

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
        isAirplay: widget.isAirplay,
        airplayHandle: widget.airplayHandle,
        whiteboard: widget.whiteboard,
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
        scrollDirection: Axis.vertical,
        child: Column(
          children: [
            // Group 1: 电源, 设备屏幕
            if (widget.controller.isHarmony)
              HarmonyPowerButton(deviceId: widget.deviceId)
            else MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.power,
                color: Theme.of(context).appColors.toolbarForeground,
              ),
              tooltip: context.l10n.t('power'),
              shortcut: MirrorShortcut.power,
              onPressed: () async {
                final result = await pressPowerKeyAndResetScreenPower(
                        actions: actions,
                        deviceId: widget.deviceId,
                        screenPowerOffNotifier: ref.read(
                          screenPowerOffProvider(widget.deviceId).notifier,
                        ),
                      );
                if (!result.isSuccess && context.mounted) {
                  AppToast.show(context, result.message, isError: true);
                }
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
                shortcut: MirrorShortcut.screenPower,
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
              shortcut: MirrorShortcut.volumeUp,
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
              shortcut: MirrorShortcut.volumeDown,
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
                shortcut: MirrorShortcut.back,
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
            if (!widget.controller.isAppMirror)
              MirrorToolbarButton(
                icon: Icon(
                  Icons.radio_button_unchecked,
                  color: Theme.of(context).appColors.toolbarForeground,
                ),
                tooltip: context.l10n.t('home'),
                shortcut: MirrorShortcut.home,
                onPressed: () {
                  actions.keyEvent(widget.deviceId, 3);
                },
              ),
            if (!widget.controller.isIos && !widget.controller.isAppMirror)
              MirrorToolbarButton(
                icon: Icon(
                  Icons.crop_square,
                  color: Theme.of(context).appColors.toolbarForeground,
                ),
                tooltip: context.l10n.t('menuKey'),
                shortcut: MirrorShortcut.recentApps,
                onPressed: () => actions.keyEvent(widget.deviceId, 187),
              ),
            MirrorClipboardInputButton(
              deviceId: widget.deviceId,
              controller: widget.controller,
            ),
            if (!widget.controller.isHarmony && !widget.controller.isIos)
              MirrorClipboardButton(
                deviceId: widget.deviceId,
                deviceName: widget.deviceName,
              ),
            const MirrorToolbarDivider(),

            // Group 5: 截图, 录屏, 前台窗口
            // 鸿蒙投屏隐藏前台窗口入口。
            if (!widget.controller.isHarmony)
            MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.scope,
                color: Theme.of(context).appColors.toolbarForeground,
              ),
              tooltip: context.l10n.t('focus'),
              shortcut: MirrorShortcut.focus,
              onPressed: () => _showForegroundWindow(context, actions),
            ),
            MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.camera,
                color: Theme.of(context).appColors.toolbarForeground,
              ),
              tooltip: context.l10n.t('screenshotTooltip'),
              shortcut: MirrorShortcut.screenshot,
              longPressShortcut: MirrorShortcut.saveScreenshot,
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
            if (widget.whiteboard != null)
              MirrorWhiteboardControls(controller: widget.whiteboard!),
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
              shortcut: MirrorShortcut.recording,
              isLoading: recordState.isStopping,
              badge: recordState.isRecording
                  ? const MirrorPulsingRecordBadge()
                  : null,
              onPressed: () {
                final displayId = widget.controller.isAppMirror
                    ? ref
                        .read(embeddedScrcpyServiceProvider)
                        .getVirtualDisplayId(widget.deviceId)
                    : null;
                if (widget.controller.isAppMirror && displayId == null) {
                  AppToast.show(
                    context,
                    '应用副屏尚未准备完成，无法录屏',
                    isError: true,
                  );
                  return;
                }
                toggleMirrorScreenRecording(
                  context,
                  ref,
                  widget.deviceId,
                  displayId: displayId,
                );
              },
            ),
            if (recordState.isRecording) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
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

            // 鸿蒙投屏隐藏手机设置入口。
            if (!widget.controller.isHarmony)
            MirrorToolbarButton(
              icon: DeviceSettingsIcon(
                color: Theme.of(context).appColors.toolbarForeground,
                size: 18,
              ),
              tooltip: context.l10n.t('deviceSettings'),
              shortcut: MirrorShortcut.deviceSettings,
              onPressed: () => showDeviceSettingsPopup(
                context: context,
                deviceId: widget.deviceId,
                isHarmony: widget.controller.isHarmony,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
