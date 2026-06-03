part of '../dashboard_screen.dart';

class MirrorSideToolbar extends ConsumerWidget {
  const MirrorSideToolbar({
    super.key,
    required this.deviceId,
    this.isStandalone = false,
  });

  final String deviceId;
  final bool isStandalone;

  Future<bool> _setScreenPowerMode(String deviceId, bool powerOn) async {
    final buffer = ByteData(2);
    buffer.setUint8(0, 10); // CONTROL_MSG_TYPE_SET_SCREEN_POWER_MODE
    buffer.setUint8(1, powerOn ? 2 : 0); // 2 = normal (on), 0 = off
    final message = buffer.buffer.asUint8List();
    return ScrcpyFlutter.sendControl(deviceId: deviceId, controlMessage: message);
  }

  Future<void> _rotateLandscape(WidgetRef ref, String deviceId) async {
    await ref.read(adbServiceProvider).shellArgs(deviceId, ['settings', 'put', 'system', 'accelerometer_rotation', '0']);
    await ref.read(adbServiceProvider).shellArgs(deviceId, ['settings', 'put', 'system', 'user_rotation', '1']);
  }

  Future<void> _rotatePortrait(WidgetRef ref, String deviceId) async {
    await ref.read(adbServiceProvider).shellArgs(deviceId, ['settings', 'put', 'system', 'accelerometer_rotation', '0']);
    await ref.read(adbServiceProvider).shellArgs(deviceId, ['settings', 'put', 'system', 'user_rotation', '0']);
  }

  Future<void> _takeScreenshot(BuildContext context, WidgetRef ref, String deviceId) async {
    try {
      final bytes = await ref.read(adbServiceProvider).captureScreenshot(deviceId);
      
      final location = await getSaveLocation(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PNG Image', extensions: ['png']),
        ],
        suggestedName: 'screenshot_${deviceId}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      if (location == null) return;

      final file = File(location.path);
      await file.writeAsBytes(bytes);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.t('saveSuccess')}: ${location.path}'),
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

  Future<void> _toggleScreenRecording(BuildContext context, WidgetRef ref) async {
    final recordState = ref.read(screenRecordProvider(deviceId));
    final recordNotifier = ref.read(screenRecordProvider(deviceId).notifier);

    if (recordState.isRecording) {
      try {
        final remotePath = await recordNotifier.stop();
        if (remotePath == null) return;

        final location = await getSaveLocation(
          acceptedTypeGroups: [
            const XTypeGroup(label: 'MP4 Video', extensions: ['mp4']),
          ],
          suggestedName: 'screenrecord_${deviceId}_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );

        if (location != null) {
          final pullResult = await ref.read(fileManagerServiceProvider).pull(
            deviceId,
            remotePath,
            location.path,
          );

          if (pullResult.isSuccess) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.l10n.t('recordSuccess').replaceAll('{path}', location.path)),
                  backgroundColor: const Color(0xff09c47c),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          } else {
            throw Exception(pullResult.stderr.isNotEmpty ? pullResult.stderr : 'File transfer failed');
          }
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
          await ref.read(fileManagerServiceProvider).delete(
            deviceId,
            '/sdcard/adb_screenrecord_temp.mp4',
          );
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

  Future<void> _openStandaloneMirror(
    BuildContext context,
    WidgetRef ref,
    String deviceId,
  ) async {
    final registeredDevices = ref.read(deviceRegistryProvider);
    final matchedDevice = registeredDevices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => RegisteredDevice(
        id: deviceId,
        serial: deviceId,
        status: 'device',
        isOnline: true,
      ),
    );
    final deviceName = matchedDevice.displayName;

    await ref
        .read(activeEmbeddedMirrorProvider(deviceId).notifier)
        .forceStop();

    try {
      final window = await DesktopMultiWindow.createWindow(jsonEncode({
        'type': 'mirror',
        'deviceId': deviceId,
        'deviceName': deviceName,
      }));
      await window.setFrame(const Offset(100, 100) & const Size(480, 800));
      await window.center();
      await window.setTitle('投屏 - $deviceName');
      await window.show();
    } catch (e) {
      debugPrint('Failed to open standalone mirror window: $e');
    }
  }

  Future<void> _openExternalMirror(
    BuildContext context,
    WidgetRef ref,
    String deviceId,
  ) async {
    // 1. If embedded mirroring is active, stop it first.
    final textureId = ref.read(activeEmbeddedMirrorProvider(deviceId));
    if (textureId != null) {
      await ref
          .read(activeEmbeddedMirrorProvider(deviceId).notifier)
          .forceStop();
    }

    try {
      final settings = ref.read(appSettingsProvider);
      final bitrateMbps = (settings.mirrorVideoBitrate / 1000000).round();
      final options = ScrcpyLaunchOptions(
        maxSize: settings.mirrorMaxSize == 0 ? 1920 : settings.mirrorMaxSize,
        videoBitRate: '${bitrateMbps}M',
        alwaysOnTop: settings.scrcpyAlwaysOnTop,
        noAudio: !settings.mirrorAudioEnabled,
      );

      final session = await ref.read(scrcpyServiceProvider).start(
        deviceId: deviceId,
        options: options,
      );
      ref.read(scrcpySessionsProvider.notifier).add(session);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已启动系统原生投屏，音频已同步转发到电脑播放'),
            backgroundColor: Color(0xff2ec46b),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('启动外部原生投屏失败: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(deviceActionServiceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isScreenOff = ref.watch(screenPowerOffProvider(deviceId));
    final recordState = ref.watch(screenRecordProvider(deviceId));

    final backgroundColor = isDark
        ? const Color(0xff1e1e1e)
        : const Color(0xffffffff);
    final borderColor = isDark
        ? const Color(0xff2d2d2d)
        : const Color(0xffeceef1);

    return Container(
      width: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isStandalone) ...[
            _ToolbarButton(
              icon: Icon(Icons.open_in_new, color: isDark ? Colors.white70 : Colors.black87),
              tooltip: '独立窗口显示',
              onPressed: () => _openStandaloneMirror(context, ref, deviceId),
            ),
            _ToolbarButton(
              icon: Icon(Icons.launch, color: isDark ? Colors.white70 : Colors.black87),
              tooltip: '开启系统原生投屏(支持音频)',
              onPressed: () => _openExternalMirror(context, ref, deviceId),
            ),
            const Divider(height: 12, indent: 8, endIndent: 8),
          ],
          // 1. Power key
          _ToolbarButton(
            icon: Icon(CupertinoIcons.power, color: isDark ? Colors.white70 : Colors.black87),
            tooltip: context.l10n.t('power'),
            onPressed: () => actions.keyEvent(deviceId, 26),
          ),
          // 2. Physical screen power off/on
          _ToolbarButton(
            icon: Icon(
              isScreenOff ? Icons.mobile_off : Icons.smartphone,
              color: isScreenOff ? Colors.orange : (isDark ? Colors.white70 : Colors.black87),
            ),
            tooltip: context.l10n.t('screenPowerToggle'),
            onPressed: () async {
              final nextState = !isScreenOff;
              final success = await _setScreenPowerMode(deviceId, !nextState);
              if (success) {
                ref.read(screenPowerOffProvider(deviceId).notifier).setOff(nextState);
              }
            },
          ),
          const Divider(height: 12, indent: 8, endIndent: 8),
          // 3. Vol Up
          _ToolbarButton(
            icon: Icon(CupertinoIcons.volume_up, color: isDark ? Colors.white70 : Colors.black87),
            tooltip: context.l10n.t('volumeUp'),
            onPressed: () => actions.volumeUp(deviceId),
          ),
          // 4. Vol Down
          _ToolbarButton(
            icon: Icon(CupertinoIcons.volume_down, color: isDark ? Colors.white70 : Colors.black87),
            tooltip: context.l10n.t('volumeDown'),
            onPressed: () => actions.volumeDown(deviceId),
          ),
          // Notification Bar
          _ToolbarButton(
            icon: Icon(CupertinoIcons.bell, color: isDark ? Colors.white70 : Colors.black87),
            tooltip: context.l10n.t('notificationBar'),
            onPressed: () => _runAdbAction(
              context,
              ref,
              actions.openNotificationBar(deviceId),
            ),
          ),
          // Focus Window (Current Focus)
          _ToolbarButton(
            icon: Icon(CupertinoIcons.viewfinder, color: isDark ? Colors.white70 : Colors.black87),
            tooltip: context.l10n.t('focus'),
            onPressed: () => _showAdbResult(
              context,
              ref,
              actions.currentFocus(deviceId),
            ),
          ),
          const Divider(height: 12, indent: 8, endIndent: 8),
          // 5. Screenshot
          _ToolbarButton(
            icon: Icon(CupertinoIcons.camera, color: isDark ? Colors.white70 : Colors.black87),
            tooltip: context.l10n.t('screenshot'),
            onPressed: () => _takeScreenshot(context, ref, deviceId),
          ),
          // 6. Screen Record
          _ToolbarButton(
            icon: Icon(
              recordState.isRecording ? CupertinoIcons.stop : CupertinoIcons.videocam,
              color: recordState.isRecording ? Colors.red : (isDark ? Colors.white70 : Colors.black87),
            ),
            tooltip: recordState.isRecording ? context.l10n.t('stopRecord') : context.l10n.t('startRecord'),
            isLoading: recordState.isStopping,
            badge: recordState.isRecording ? const _PulsingRecordBadge() : null,
            onPressed: () => _toggleScreenRecording(context, ref),
          ),
          if (recordState.isRecording) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _formatDuration(recordState.durationSeconds),
                style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
          // 7. Zoom/Layout Inspector
          _ToolbarButton(
            icon: Icon(CupertinoIcons.zoom_in, color: isDark ? Colors.white70 : Colors.black87),
            tooltip: context.l10n.t('inspectLayout'),
            onPressed: () {
              ref.read(selectedToolTabProvider.notifier).select(8); // Switch to Layout Tab
            },
          ),
          const Divider(height: 12, indent: 8, endIndent: 8),
          // 8. Rotate Landscape
          _ToolbarButton(
            icon: Icon(Icons.rotate_right, color: isDark ? Colors.white70 : Colors.black87),
            tooltip: context.l10n.t('rotateLandscape'),
            onPressed: () => _rotateLandscape(ref, deviceId),
          ),
          // 9. Rotate Portrait
          _ToolbarButton(
            icon: Icon(Icons.rotate_left, color: isDark ? Colors.white70 : Colors.black87),
            tooltip: context.l10n.t('rotatePortrait'),
            onPressed: () => _rotatePortrait(ref, deviceId),
          ),
          const Divider(height: 12, indent: 8, endIndent: 8),
          // 10. Back
          _ToolbarButton(
            icon: Icon(Icons.chevron_left, color: isDark ? Colors.white70 : Colors.black87),
            tooltip: context.l10n.t('back'),
            onPressed: () => actions.keyEvent(deviceId, 4),
          ),
          // 11. Home
          _ToolbarButton(
            icon: Icon(Icons.radio_button_unchecked, color: isDark ? Colors.white70 : Colors.black87),
            tooltip: context.l10n.t('home'),
            onPressed: () => actions.keyEvent(deviceId, 3),
          ),
          // 12. Recents
          _ToolbarButton(
            icon: Icon(Icons.crop_square, color: isDark ? Colors.white70 : Colors.black87),
            tooltip: context.l10n.t('menuKey'), // Recents / Menu
            onPressed: () => actions.keyEvent(deviceId, 187),
          ),
        ],
      ),
    );
  }
}

class _PulsingRecordBadge extends StatefulWidget {
  const _PulsingRecordBadge();

  @override
  State<_PulsingRecordBadge> createState() => _PulsingRecordBadgeState();
}

class _PulsingRecordBadgeState extends State<_PulsingRecordBadge> with SingleTickerProviderStateMixin {
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

class _ToolbarButton extends StatefulWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isLoading = false,
    this.badge,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? badge;

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
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
      margin: const EdgeInsets.only(right: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedScale(
          scale: _isHovered ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                iconSize: 20,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: _isHovered ? hoverBg : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: widget.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : widget.icon,
                onPressed: widget.isLoading ? null : widget.onPressed,
              ),
              if (widget.badge != null)
                Positioned(
                  top: 2,
                  right: 2,
                  child: widget.badge!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
