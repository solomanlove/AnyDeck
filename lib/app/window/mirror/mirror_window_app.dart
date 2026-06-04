import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../../l10n/app_localizations.dart';
import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../../features/dashboard/presentation/control/embedded_scrcpy_viewer.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../core/scrcpy/scrcpy_launch_options.dart';
import '../../../core/providers/app_providers.dart';
import 'mirror_floating_toolbar.dart';

/// 投屏独立窗口应用入口。
class MirrorWindowApp extends ConsumerWidget {
  const MirrorWindowApp({
    super.key,
    required this.windowId,
    required this.argument,
  });

  final int windowId;
  final Map<String, dynamic> argument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final deviceId = argument['deviceId'] as String? ?? '';
    final deviceName = argument['deviceName'] as String? ?? 'Device';

    return MaterialApp(
      onGenerateTitle: (context) => deviceName,
      debugShowCheckedModeBanner: false,
      locale: settings.language.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: settings.themeMode,
      home: MirrorWindowContent(
        deviceId: deviceId,
        deviceName: deviceName,
        windowId: windowId,
      ),
    );
  }
}

class MirrorWindowContent extends ConsumerStatefulWidget {
  const MirrorWindowContent({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.windowId,
  });

  final String deviceId;
  final String deviceName;
  final int windowId;

  @override
  ConsumerState<MirrorWindowContent> createState() =>
      _MirrorWindowContentState();
}

class _MirrorWindowContentState extends ConsumerState<MirrorWindowContent>
    with WindowListener {
  String? _errorMessage;
  bool _isLoading = true;
  bool _isFullScreen = false;
  bool _isAlwaysOnTop = false;
  late final FocusNode _keyboardFocusNode;
  DateTime? _lastPointerDownTime;

  static const _windowChannel = MethodChannel('adb_manage/window');

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode = FocusNode(debugLabel: 'MirrorWindowKeyboard');
    _isAlwaysOnTop = ref.read(appSettingsProvider).scrcpyAlwaysOnTop;
    if (Platform.isMacOS) {
      _windowChannel.setMethodCallHandler((call) async {
        if (call.method == 'onWindowEnterFullScreen') {
          if (mounted) {
            setState(() {
              _isFullScreen = true;
            });
          }
        } else if (call.method == 'onWindowLeaveFullScreen') {
          if (mounted) {
            setState(() {
              _isFullScreen = false;
            });
          }
        }
      });
      _windowChannel.invokeMethod('initWindow').catchError((e) {
        debugPrint('Failed to initialize subwindow listeners: $e');
      });
    } else {
      windowManager.addListener(this);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _startMirroring();
      try {
        await _windowChannel.invokeMethod('setAlwaysOnTop', _isAlwaysOnTop);
      } catch (e) {
        debugPrint('Failed to set always on top in initState: $e');
      }
    });
  }

  @override
  void dispose() {
    if (Platform.isMacOS) {
      _windowChannel.setMethodCallHandler(null);
    } else {
      windowManager.removeListener(this);
    }
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    setState(() {
      _isFullScreen = true;
    });
  }

  @override
  void onWindowLeaveFullScreen() {
    setState(() {
      _isFullScreen = false;
    });
  }

  void _toggleFullScreen(bool fullscreen) async {
    if (Platform.isMacOS) {
      try {
        await _windowChannel.invokeMethod('setFullScreen', fullscreen);
      } catch (e) {
        debugPrint('Failed to set fullscreen on macOS: $e');
      }
    } else {
      await windowManager.setFullScreen(fullscreen);
    }
    if (fullscreen && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已进入全屏，按 ESC 或双击屏幕可退出全屏'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

  Future<void> _startMirroring() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final activeMirror = ref.read(
        activeEmbeddedMirrorProvider(widget.deviceId),
      );
      if (activeMirror == null) {
        await ref
            .read(activeEmbeddedMirrorProvider(widget.deviceId).notifier)
            .toggleMirroring();
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textureId = ref.watch(activeEmbeddedMirrorProvider(widget.deviceId));
    final isMirrorActive = textureId != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final headerBgColor = isDark
        ? Theme.of(context).cardColor
        : const Color(0xffffffff);
    final borderColor = isDark
        ? const Color(0xff2d2d2d)
        : const Color(0xffeceef1);

    Widget contentWidget;
    if (_isLoading) {
      contentWidget = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在启动投屏服务...', style: TextStyle(fontSize: 14)),
          ],
        ),
      );
    } else if (_errorMessage != null) {
      contentWidget = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                '投屏启动失败',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _startMirroring,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    } else if (isMirrorActive) {
      contentWidget = Column(
        children: [
          if (!_isFullScreen)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Center(
                child: MirrorFloatingToolbar(
                  deviceId: widget.deviceId,
                  windowId: widget.windowId,
                ),
              ),
            ),
          Expanded(
            child: ClipRRect(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) {
                  final now = DateTime.now();
                  if (_lastPointerDownTime != null &&
                      now.difference(_lastPointerDownTime!) <
                          const Duration(milliseconds: 300)) {
                    _toggleFullScreen(!_isFullScreen);
                  }
                  _lastPointerDownTime = now;
                },
                child: EmbeddedScrcpyViewer(deviceId: widget.deviceId),
              ),
            ),
          ),
        ],
      );
    } else {
      contentWidget = const Center(child: Text('未连接或投屏已停止'));
    }

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xff121212)
          : const Color(0xfff8f9fa),
      body: KeyboardListener(
        focusNode: _keyboardFocusNode,
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            if (_isFullScreen) {
              _toggleFullScreen(false);
            }
          }
        },
        child: Column(
          children: [
            if (!_isFullScreen)
              Container(
                height: 36, // 调小高度以在 macOS 上更紧凑，确保标题上下居中
                padding: EdgeInsets.only(
                  left: Platform.isMacOS ? 80 : 16,
                  right: 16,
                ),
                decoration: BoxDecoration(
                  color: headerBgColor,
                  border: Border(
                    bottom: BorderSide(color: borderColor, width: 1),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      widget.deviceName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    MirrorToolbarButton(
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
                    const SizedBox(width: 4),
                    MirrorToolbarButton(
                      icon: Icon(
                        _isFullScreen
                            ? CupertinoIcons.fullscreen_exit
                            : CupertinoIcons.fullscreen,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      tooltip: _isFullScreen ? '退出全屏' : '全屏显示',
                      onPressed: () => _toggleFullScreen(!_isFullScreen),
                    ),
                    const SizedBox(width: 4),
                    MirrorToolbarButton(
                      icon: Icon(
                        CupertinoIcons.settings,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      tooltip: '投屏画质设置',
                      onPressed: () => _showSettingsDialog(context),
                    ),
                  ],
                ),
              ),
            Expanded(child: contentWidget),
          ],
        ),
      ),
    );
  }
}
