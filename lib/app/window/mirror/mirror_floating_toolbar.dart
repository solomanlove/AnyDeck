import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:scrcpy_flutter/scrcpy_flutter.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../../settings/app_settings_controller.dart';
import '../../../core/device_actions/device_action_service.dart';
import '../../../core/scrcpy/screen_record_provider.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../core/scrcpy/scrcpy_launch_options.dart';
import '../../../core/scrcpy/scrcpy_keycode_helper.dart';
import '../../../core/providers/app_providers.dart';
import '../../../app/l10n/app_localizations.dart';

class MirrorFloatingToolbar extends ConsumerStatefulWidget {
  const MirrorFloatingToolbar({
    super.key,
    required this.deviceId,
    required this.windowId,
    required this.isFullScreen,
    required this.onToggleFullScreen,
  });

  final String deviceId;
  final int windowId;
  final bool isFullScreen;
  final VoidCallback onToggleFullScreen;

  @override
  ConsumerState<MirrorFloatingToolbar> createState() =>
      _MirrorFloatingToolbarState();
}

class _MirrorFloatingToolbarState extends ConsumerState<MirrorFloatingToolbar> {
  bool _isExpanded = false;
  bool _isAlwaysOnTop = false;

  static const _windowChannel = MethodChannel('adb_manage/window');

  @override
  void initState() {
    super.initState();
    // 默认读取全局设置里的置顶状态，或者初始化时为 false
    _isAlwaysOnTop = ref.read(appSettingsProvider).scrcpyAlwaysOnTop;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _windowChannel.invokeMethod('setAlwaysOnTop', _isAlwaysOnTop);
      } catch (e) {
        debugPrint('Failed to set always on top in initState: $e');
      }
    });
  }

  Future<void> _toggleAlwaysOnTop() async {
    final nextState = !_isAlwaysOnTop;
    try {
      await _windowChannel.invokeMethod('setAlwaysOnTop', nextState);
      setState(() {
        _isAlwaysOnTop = nextState;
      });
    } catch (e) {
      debugPrint('Failed to toggle always on top: $e');
    }
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

      final location = await getSaveLocation(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PNG Image', extensions: ['png']),
        ],
        suggestedName:
            'screenshot_${deviceId}_${DateTime.now().millisecondsSinceEpoch}.png',
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

  Future<void> _toggleScreenRecording(BuildContext context) async {
    final recordState = ref.read(screenRecordProvider(widget.deviceId));
    final recordNotifier = ref.read(
      screenRecordProvider(widget.deviceId).notifier,
    );

    if (recordState.isRecording) {
      try {
        final remotePath = await recordNotifier.stop();
        if (remotePath == null) return;

        final location = await getSaveLocation(
          acceptedTypeGroups: [
            const XTypeGroup(label: 'MP4 Video', extensions: ['mp4']),
          ],
          suggestedName:
              'screenrecord_${widget.deviceId}_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );

        if (location != null) {
          final pullResult = await ref
              .read(fileManagerServiceProvider)
              .pull(widget.deviceId, remotePath, location.path);

          if (pullResult.isSuccess) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n
                        .t('recordSuccess')
                        .replaceAll('{path}', location.path),
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

  void _showSettingsDialog(BuildContext context) {
    final settings = ref.read(appSettingsProvider);
    int selectedBitrate = settings.mirrorVideoBitrate;
    int selectedMaxSize = settings.mirrorMaxSize;
    bool selectedAudio = settings.mirrorAudioEnabled;

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final cardColor = isDark
                ? const Color(0xff1e1e1e)
                : const Color(0xffffffff);
            final titleStyle = Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold);

            return AlertDialog(
              backgroundColor: cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.settings,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  const SizedBox(width: 8),
                  const Text('投屏画质设置'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('视频比特率 (Video Bitrate)', style: titleStyle),
                    const SizedBox(height: 8),
                    DropdownButton<int>(
                      value: selectedBitrate,
                      isExpanded: true,
                      dropdownColor: cardColor,
                      items: const [
                        DropdownMenuItem(
                          value: 2000000,
                          child: Text('2 Mbps (极低/流畅)'),
                        ),
                        DropdownMenuItem(
                          value: 4000000,
                          child: Text('4 Mbps (低)'),
                        ),
                        DropdownMenuItem(
                          value: 8000000,
                          child: Text('8 Mbps (默认/推荐)'),
                        ),
                        DropdownMenuItem(
                          value: 16000000,
                          child: Text('16 Mbps (超清)'),
                        ),
                        DropdownMenuItem(
                          value: 32000000,
                          child: Text('32 Mbps (极清/高带宽)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedBitrate = val);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    Text('最佳尺寸 (Max Size / 分辨率)', style: titleStyle),
                    const SizedBox(height: 8),
                    DropdownButton<int>(
                      value: selectedMaxSize,
                      isExpanded: true,
                      dropdownColor: cardColor,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('原始大小 (无限制)')),
                        DropdownMenuItem(
                          value: 720,
                          child: Text('720p (1280x720)'),
                        ),
                        DropdownMenuItem(
                          value: 1080,
                          child: Text('1080p (1920x1080, 默认)'),
                        ),
                        DropdownMenuItem(
                          value: 1440,
                          child: Text('1440p (2K / 2560x1440)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedMaxSize = val);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('音频转发 (Audio Forwarding)', style: titleStyle),
                        Switch(
                          value: selectedAudio,
                          activeTrackColor: const Color(0xff2ec46b),
                          onChanged: (val) {
                            setDialogState(() => selectedAudio = val);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '注意：当前内嵌投屏窗口因底层限制无法直接播放音频。如需使用音频转发到电脑播放，请使用外部原生投屏。',
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xff2ec46b)),
                        foregroundColor: const Color(0xff2ec46b),
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text(
                        '启动外部原生投屏 (支持音频播放)',
                        style: TextStyle(fontSize: 12),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _launchExternalMirror(context);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '注：修改设置后保存，投屏服务将自动重启以应用新画质。',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff2ec46b),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.of(context).pop();

                    // 保存配置
                    await ref
                        .read(appSettingsProvider.notifier)
                        .setMirrorVideoBitrate(selectedBitrate);
                    await ref
                        .read(appSettingsProvider.notifier)
                        .setMirrorMaxSize(selectedMaxSize);
                    await ref
                        .read(appSettingsProvider.notifier)
                        .setMirrorAudioEnabled(selectedAudio);

                    // 提示并重启
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('正在重载投屏画质设置...'),
                          duration: Duration(milliseconds: 1500),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }

                    // 自动重连投屏
                    await ref
                        .read(
                          activeEmbeddedMirrorProvider(
                            widget.deviceId,
                          ).notifier,
                        )
                        .restartMirroring();
                  },
                  child: const Text('保存并应用'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _launchExternalMirror(BuildContext context) async {
    // 1. 获取当前设置
    final settings = ref.read(appSettingsProvider);
    final bitrateMbps = (settings.mirrorVideoBitrate / 1000000).round();
    final options = ScrcpyLaunchOptions(
      maxSize: settings.mirrorMaxSize == 0 ? 1920 : settings.mirrorMaxSize,
      videoBitRate: '${bitrateMbps}M',
      alwaysOnTop: _isAlwaysOnTop,
      noAudio: !settings.mirrorAudioEnabled,
    );

    // 2. 停止内嵌投屏
    await ref
        .read(activeEmbeddedMirrorProvider(widget.deviceId).notifier)
        .forceStop();

    // 3. 启动外部投屏
    try {
      final session = await ref
          .read(scrcpyServiceProvider)
          .start(deviceId: widget.deviceId, options: options);
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

      // 4. 关闭当前独立投屏窗口
      await WindowController.fromWindowId(widget.windowId).close();
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final actions = ref.read(deviceActionServiceProvider);
    final isScreenOff = ref.watch(screenPowerOffProvider(widget.deviceId));
    final recordState = ref.watch(screenRecordProvider(widget.deviceId));

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: _isExpanded
          ? _buildExpandedToolbar(
              context,
              actions,
              isDark,
              isScreenOff,
              recordState,
            )
          : _buildCollapsedToolbar(context, isDark),
    );
  }

  Widget _buildCollapsedToolbar(BuildContext context, bool isDark) {
    final hoverBg = isDark
        ? Colors.black.withValues(alpha: 0.8)
        : Colors.white.withValues(alpha: 0.85);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.08);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _isExpanded = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: hoverBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.chevron_down,
                size: 14,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              const SizedBox(width: 6),
              Text(
                '工具栏',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedToolbar(
    BuildContext context,
    DeviceActionService actions,
    bool isDark,
    bool isScreenOff,
    ScreenRecordState recordState,
  ) {
    final hoverBg = isDark
        ? Colors.black.withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.9);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.black.withValues(alpha: 0.1);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // 吸收点击事件，防止穿透
      child: Container(
        constraints: const BoxConstraints(maxHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: hoverBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(CupertinoIcons.chevron_up),
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => setState(() => _isExpanded = false),
              tooltip: '收起工具栏',
            ),
            const SizedBox(width: 4),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // 1. Always On Top
                    _ToolbarButton(
                      icon: Icon(
                        _isAlwaysOnTop
                            ? CupertinoIcons.pin_fill
                            : CupertinoIcons.pin,
                        color: _isAlwaysOnTop
                            ? Colors.orange
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                      tooltip: _isAlwaysOnTop ? '取消置顶' : '置顶窗口',
                      onPressed: _toggleAlwaysOnTop,
                    ),
                    // 1.5 Full Screen
                    _ToolbarButton(
                      icon: Icon(
                        widget.isFullScreen
                            ? CupertinoIcons.fullscreen_exit
                            : CupertinoIcons.fullscreen,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      tooltip: widget.isFullScreen ? '退出全屏' : '全屏显示',
                      onPressed: widget.onToggleFullScreen,
                    ),
                    // 2. Settings
                    _ToolbarButton(
                      icon: Icon(
                        CupertinoIcons.settings,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      tooltip: '投屏画质设置',
                      onPressed: () => _showSettingsDialog(context),
                    ),
                    // 2.5. Launch External Mirror (System Native)
                    _ToolbarButton(
                      icon: Icon(
                        Icons.open_in_new,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      tooltip: '开启系统原生投屏 (支持音频/电脑播放)',
                      onPressed: () => _launchExternalMirror(context),
                    ),
                    const _VerticalDivider(),
                    // 3. Power Key
                    _ToolbarButton(
                      icon: Icon(
                        CupertinoIcons.power,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      tooltip: context.l10n.t('power'),
                      onPressed: () => actions.keyEvent(widget.deviceId, 26),
                    ),
                    // 4. Screen Off/On
                    _ToolbarButton(
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
                              .read(
                                screenPowerOffProvider(
                                  widget.deviceId,
                                ).notifier,
                              )
                              .setOff(nextState);
                        }
                      },
                    ),
                    const _VerticalDivider(),
                    // 5. Volume Up/Down
                    _ToolbarButton(
                      icon: Icon(
                        CupertinoIcons.volume_up,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      tooltip: context.l10n.t('volumeUp'),
                      onPressed: () => actions.volumeUp(widget.deviceId),
                    ),
                    _ToolbarButton(
                      icon: Icon(
                        CupertinoIcons.volume_down,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      tooltip: context.l10n.t('volumeDown'),
                      onPressed: () => actions.volumeDown(widget.deviceId),
                    ),
                    // 6. Notifications
                    _ToolbarButton(
                      icon: Icon(
                        CupertinoIcons.bell,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      tooltip: context.l10n.t('notificationBar'),
                      onPressed: () =>
                          actions.openNotificationBar(widget.deviceId),
                    ),
                    // 7. Focus Window
                    _ToolbarButton(
                      icon: Icon(
                        CupertinoIcons.scope,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      tooltip: context.l10n.t('focus'),
                      onPressed: () async {
                        final res = await actions.currentFocus(widget.deviceId);
                        if (context.mounted) {
                          showDialog<void>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('当前焦点窗口'),
                              content: SelectableText(res.stdout),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('确定'),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                    ),
                    // Clipboard Input Text T
                    _ToolbarButton(
                      icon: Text(
                        'T',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      tooltip: '获取剪切板并输入文本',
                      onPressed: () async {
                        final clipboardData = await Clipboard.getData(
                          Clipboard.kTextPlain,
                        );
                        if (clipboardData != null &&
                            clipboardData.text != null &&
                            clipboardData.text!.isNotEmpty) {
                          final text = clipboardData.text!;
                          final message =
                              ScrcpyKeycodeHelper.serializeTextEvent(text);
                          final success = await ScrcpyFlutter.sendControl(
                            deviceId: widget.deviceId,
                            controlMessage: message,
                          );
                          if (!success && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('发送剪切板文本失败，请确保投屏运行中'),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('剪切板为空或获取失败'),
                                backgroundColor: Colors.orange,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    const _VerticalDivider(),
                    // 8. Screenshot
                    _ToolbarButton(
                      icon: Icon(
                        CupertinoIcons.camera,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      tooltip: context.l10n.t('screenshot'),
                      onPressed: () =>
                          _takeScreenshot(context, widget.deviceId),
                    ),
                    // 9. Screen Record
                    _ToolbarButton(
                      icon: Icon(
                        recordState.isRecording
                            ? CupertinoIcons.stop
                            : CupertinoIcons.videocam,
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
                    const _VerticalDivider(),

                    // 11. Navigation Bar
                    _ToolbarButton(
                      icon: Icon(
                        Icons.chevron_left,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      tooltip: context.l10n.t('back'),
                      onPressed: () => actions.keyEvent(widget.deviceId, 4),
                    ),
                    _ToolbarButton(
                      icon: Icon(
                        Icons.radio_button_unchecked,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      tooltip: context.l10n.t('home'),
                      onPressed: () => actions.keyEvent(widget.deviceId, 3),
                    ),
                    _ToolbarButton(
                      icon: Icon(
                        Icons.crop_square,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      tooltip: context.l10n.t('menuKey'),
                      onPressed: () => actions.keyEvent(widget.deviceId, 187),
                    ),
                  ],
                ),
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
      margin: const EdgeInsets.only(bottom: 8),
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
                iconSize: 18,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
