import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrcpy_flutter/scrcpy_flutter.dart';

import '../../../core/device_actions/device_action_service.dart';
import '../../../core/scrcpy/screen_record_provider.dart';
import '../../../core/scrcpy/scrcpy_keycode_helper.dart';
import '../../../core/providers/app_providers.dart';
import '../../../app/l10n/app_localizations.dart';
import '../../settings/app_settings_controller.dart';
import '../../../features/dashboard/presentation/control/device_settings_popup.dart';
import '../../../features/dashboard/presentation/widgets/device_power_actions.dart';
import 'mirror_back_long_press_handler.dart';
import 'mirror_volume_long_press_handler.dart';
import 'mirror_window_controller.dart';

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

  Future<bool> _setScreenPowerMode(String deviceId, bool powerOn) async {
    final buffer = ByteData(2);
    buffer.setUint8(0, 10); // CONTROL_MSG_TYPE_SET_SCREEN_POWER_MODE
    buffer.setUint8(1, powerOn ? 2 : 0); // 2 = normal (on), 0 = off
    final message = buffer.buffer.asUint8List();
    return ScrcpyFlutter.sendControl(
      deviceId: deviceId,
      controlMessage: message,
    );
  }

  Future<void> _takeScreenshot(BuildContext context, String deviceId) async {
    try {
      final bytes = await ref
          .read(adbServiceProvider)
          .captureScreenshot(deviceId);

      final settings = ref.read(appSettingsProvider);
      final hostPlatform = ref.read(hostPlatformServiceProvider);
      final savePath = hostPlatform.generateScreenshotPath(
        settings.screenshotSavePath,
        deviceId,
      );
      final file = File(savePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);

      // 复制到剪切板
      final copied = await hostPlatform.copyImageToClipboard(bytes);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10n.t('saveSuccess')}: $savePath${copied ? " (已复制到剪贴板)" : ""}',
            ),
            backgroundColor: const Color(0xff09c47c),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.t('error')}: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _toggleScreenRecording(BuildContext context) async {
    final recordState = ref.read(screenRecordProvider(widget.deviceId));
    final recordNotifier = ref.read(
      screenRecordProvider(widget.deviceId).notifier,
    );

    if (recordState.isRecording) {
      try {
        final remotePath = await recordNotifier.stop();
        if (remotePath == null) return;

        final settings = ref.read(appSettingsProvider);
        final hostPlatform = ref.read(hostPlatformServiceProvider);
        final localSavePath = hostPlatform.generateRecordPath(
          settings.screenshotSavePath,
          widget.deviceId,
        );
        final file = File(localSavePath);
        await file.parent.create(recursive: true);

        final pullResult = await ref
            .read(fileManagerServiceProvider)
            .pull(widget.deviceId, remotePath, localSavePath);

        if (pullResult.isSuccess) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.l10n
                      .t('recordSuccess')
                      .replaceAll('{path}', localSavePath),
                ),
                backgroundColor: const Color(0xff09c47c),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          throw Exception(
            pullResult.stderr.isNotEmpty
                ? pullResult.stderr
                : 'File transfer failed',
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${context.l10n.t('recordFailed')}: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        try {
          await ref
              .read(fileManagerServiceProvider)
              .delete(widget.deviceId, '/sdcard/adb_screenrecord_temp.mp4');
        } catch (_) {}
      }
    } else {
      try {
        await recordNotifier.start();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${context.l10n.t('recordFailed')}: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
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
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              tooltip: context.l10n.t('power'),
              onPressed: () => pressPowerKeyAndResetScreenPower(
                actions: actions,
                deviceId: widget.deviceId,
                screenPowerOffNotifier: ref.read(
                  screenPowerOffProvider(widget.deviceId).notifier,
                ),
              ),
            ),
            MirrorToolbarButton(
              icon: Icon(
                isScreenOff ? Icons.mobile_off : Icons.smartphone,
                color: isScreenOff
                    ? Colors.orange
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
              tooltip: context.l10n.t('screenPowerToggle'),
              onPressed: () async {
                final nextState = !isScreenOff;
                final success = await _setScreenPowerMode(
                  widget.deviceId,
                  !nextState,
                );
                if (success) {
                  ref
                      .read(screenPowerOffProvider(widget.deviceId).notifier)
                      .setOff(nextState);
                }
              },
            ),
            const _VerticalDivider(),

            // Group 2: 音量+, 音量-
            MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.volume_up,
                color: isDark ? Colors.white70 : Colors.black87,
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
                color: isDark ? Colors.white70 : Colors.black87,
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
            const _VerticalDivider(),

            // Group 3: 后退, 主屏, 菜单
            MirrorToolbarButton(
              icon: Icon(
                Icons.chevron_left,
                size: 18,
                color: isDark ? Colors.white70 : Colors.black87,
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
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              tooltip: context.l10n.t('home'),
              onPressed: () => actions.keyEvent(widget.deviceId, 3),
            ),
            MirrorToolbarButton(
              icon: Icon(
                Icons.crop_square,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              tooltip: context.l10n.t('menuKey'),
              onPressed: () => actions.keyEvent(widget.deviceId, 187),
            ),
            const _VerticalDivider(),

            // Group 4: 通知栏, T
            MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.bell,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              tooltip: context.l10n.t('notificationBar'),
              onPressed: () => actions.openNotificationBar(widget.deviceId),
            ),
            MirrorToolbarButton(
              icon: Text(
                'T',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
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
                  final message = ScrcpyKeycodeHelper.serializeTextEvent(text);
                  final success = await ScrcpyFlutter.sendControl(
                    deviceId: widget.deviceId,
                    controlMessage: message,
                  );
                  if (!success && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.l10n.t('sendClipboardFailed')),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.l10n.t('clipboardEmpty')),
                        backgroundColor: Colors.orange,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
            ),
            const _VerticalDivider(),

            // Group 5: 截图, 录屏, 前台窗口
            MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.camera,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              tooltip: context.l10n.t('screenshot'),
              onPressed: () => _takeScreenshot(context, widget.deviceId),
            ),
            MirrorToolbarButton(
              icon: Icon(
                recordState.isRecording
                    ? CupertinoIcons.stop
                    : CupertinoIcons.videocam,
                size: 22,
                color: recordState.isRecording
                    ? Colors.red
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
              tooltip: recordState.isRecording
                  ? context.l10n.t('stopRecord')
                  : context.l10n.t('startRecord'),
              isLoading: recordState.isStopping,
              badge: recordState.isRecording
                  ? const _PulsingRecordBadge()
                  : null,
              onPressed: () => _toggleScreenRecording(context),
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
            MirrorToolbarButton(
              icon: Icon(
                CupertinoIcons.scope,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              tooltip: context.l10n.t('focus'),
              onPressed: () async {
                // 手动点击前台窗口图标触发识别前台应用
                widget.controller.identifyForegroundApp();

                final res = await actions.currentFocus(widget.deviceId);
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
                              color: isDark ? Colors.white70 : Colors.black87,
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
              icon: DeviceSettingsIcon(
                color: isDark ? Colors.white70 : Colors.black87,
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

class _PulsingRecordBadge extends StatefulWidget {
  const _PulsingRecordBadge();

  @override
  State<_PulsingRecordBadge> createState() => _PulsingRecordBadgeState();
}

class _PulsingRecordBadgeState extends State<_PulsingRecordBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.8, end: 1.2).animate(_controller),
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class MirrorToolbarButton extends StatefulWidget {
  const MirrorToolbarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isLoading = false,
    this.badge,
    this.onPointerDown,
    this.onPointerUp,
    this.onPointerCancel,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? badge;
  final VoidCallback? onPointerDown;
  final VoidCallback? onPointerUp;
  final VoidCallback? onPointerCancel;

  @override
  State<MirrorToolbarButton> createState() => _MirrorToolbarButtonState();
}

class _MirrorToolbarButtonState extends State<MirrorToolbarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hoverBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      margin: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedScale(
          scale: _isHovered ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: Listener(
            onPointerDown: (_) => widget.onPointerDown?.call(),
            onPointerUp: (_) => widget.onPointerUp?.call(),
            onPointerCancel: (_) => widget.onPointerCancel?.call(),
            child: Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  iconSize: 14,
                  padding: const EdgeInsets.all(2),
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: _isHovered ? hoverBg : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  icon: widget.isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : widget.icon,
                  onPressed: widget.isLoading ? null : widget.onPressed,
                ),
                if (widget.badge != null)
                  Positioned(top: 2, right: 2, child: widget.badge!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: isDark ? Colors.white24 : Colors.black12,
    );
  }
}
