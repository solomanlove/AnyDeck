import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:scrcpy_flutter/scrcpy_flutter.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';

import '../../l10n/app_localizations.dart';
import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../../features/dashboard/presentation/control/embedded_scrcpy_viewer.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../core/providers/app_providers.dart';
import 'mirror_floating_toolbar.dart';
import 'mirror_settings_dialog.dart';

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
  final GlobalKey _viewerKey = GlobalKey();

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
    if (mounted) {
      setState(() {
        _isFullScreen = fullscreen;
      });
    }
    if (Platform.isMacOS) {
      try {
        await _windowChannel.invokeMethod('setFullScreen', fullscreen);
      } catch (e) {
        debugPrint('Failed to set fullscreen on macOS: $e');
      }
    } else {
      try {
        await windowManager.setFullScreen(fullscreen);
      } catch (e) {
        debugPrint('Failed to set fullscreen: $e');
      }
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

  double _getAspectRatio(String? resolutionStr) {
    if (resolutionStr == null || resolutionStr == '-') return 9 / 16;
    final match = RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch(resolutionStr);
    if (match != null) {
      final w = int.parse(match.group(1)!);
      final h = int.parse(match.group(2)!);
      if (w > 0 && h > 0) {
        return w / h;
      }
    }
    return 9 / 16;
  }

  void _handleDoubleTap(PointerDownEvent e) async {
    final overviewAsync = ref.read(deviceOverviewProvider(widget.deviceId));
    final resolution = overviewAsync.maybeWhen(
      data: (overview) => overview.physicalResolution,
      orElse: () => null,
    );
    double aspectRatio = _getAspectRatio(resolution);

    try {
      final size = await ScrcpyFlutter.getVideoSize(deviceId: widget.deviceId);
      if (size != null && size['width']! > 0 && size['height']! > 0) {
        aspectRatio = size['width']! / size['height']!;
      }
    } catch (_) {}

    final renderBox =
        _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final viewerSize = renderBox.size;
    final double viewerW = viewerSize.width;
    final double viewerH = viewerSize.height;
    if (viewerW <= 0 || viewerH <= 0) return;

    final localPos = renderBox.globalToLocal(e.position);
    final containerRatio = viewerW / viewerH;

    bool isOnBlackBorder = false;
    if (containerRatio > aspectRatio) {
      // 左右有黑边
      final textureW = viewerH * aspectRatio;
      final leftBorder = (viewerW - textureW) / 2;
      final rightBorder = (viewerW + textureW) / 2;
      if (localPos.dx < leftBorder || localPos.dx > rightBorder) {
        isOnBlackBorder = true;
      }
    } else if (containerRatio < aspectRatio) {
      // 上下有黑边
      final textureH = viewerW / aspectRatio;
      final topBorder = (viewerH - textureH) / 2;
      final bottomBorder = (viewerH + textureH) / 2;
      if (localPos.dy < topBorder || localPos.dy > bottomBorder) {
        isOnBlackBorder = true;
      }
    }

    if (isOnBlackBorder) {
      if (_isFullScreen) {
        _toggleFullScreen(false);
      } else {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) {
            _fitWindowToAspectRatio(aspectRatio, viewerW, viewerH);
          }
        });
      }
    } else {
      debugPrint(
        '[MirrorWindow] Double tap on device screen, ignore fullscreen toggle.',
      );
    }
  }

  Future<Rect> _getWindowFrame() async {
    if (Platform.isMacOS) {
      try {
        final res = await _windowChannel.invokeMethod('getWindowFrame');
        if (res is Map) {
          final left = (res['left'] as num).toDouble();
          final top = (res['top'] as num).toDouble();
          final width = (res['width'] as num).toDouble();
          final height = (res['height'] as num).toDouble();
          return Rect.fromLTWH(left, top, width, height);
        }
      } catch (e) {
        debugPrint('Failed to get window frame on macOS: $e');
      }
      return const Rect.fromLTWH(100, 100, 480, 800);
    } else {
      return await windowManager.getBounds();
    }
  }

  Future<void> _fitWindowToAspectRatio(
    double R,
    double viewerW,
    double viewerH,
  ) async {
    if (R <= 0 || R.isNaN || R.isInfinite) {
      return;
    }
    if (viewerW <= 0 ||
        viewerH <= 0 ||
        viewerW.isNaN ||
        viewerW.isInfinite ||
        viewerH.isNaN ||
        viewerH.isInfinite) {
      return;
    }

    final Rect frame = await _getWindowFrame();
    if (frame.width.isNaN ||
        frame.width.isInfinite ||
        frame.height.isNaN ||
        frame.height.isInfinite) {
      return;
    }

    final double currentWindowW = frame.width;
    final double currentWindowH = frame.height;

    final double rc = viewerW / viewerH;
    if (rc.isNaN || rc.isInfinite || rc <= 0) {
      return;
    }

    double deltaW = 0;
    double deltaH = 0;

    if (rc > R) {
      // 左右有黑边，需要减小窗口宽度
      final targetViewerW = viewerH * R;
      deltaW = targetViewerW - viewerW;
    } else if (rc < R) {
      // 上下有黑边，需要减小窗口高度
      final targetViewerH = viewerW / R;
      deltaH = targetViewerH - viewerH;
    }

    if (deltaW.abs() < 4 && deltaH.abs() < 4) {
      return;
    }
    if (deltaW == 0 && deltaH == 0) {
      return;
    }

    final double newWindowW = currentWindowW + deltaW;
    final double newWindowH = currentWindowH + deltaH;

    if (newWindowW < 200 ||
        newWindowH < 200 ||
        newWindowW.isNaN ||
        newWindowW.isInfinite ||
        newWindowH.isNaN ||
        newWindowH.isInfinite) {
      return;
    }

    // 保持窗口中心点不变进行缩放
    final double newLeft = frame.left - deltaW / 2;
    final double newTop = frame.top - deltaH / 2;

    if (newLeft.isNaN ||
        newLeft.isInfinite ||
        newTop.isNaN ||
        newTop.isInfinite) {
      return;
    }

    final windowController = WindowController.fromWindowId(widget.windowId);
    windowController
        .setFrame(Rect.fromLTWH(newLeft, newTop, newWindowW, newWindowH))
        .catchError((e) {
          debugPrint('Failed to set window frame: $e');
        });
  }

  Future<void> _handleDrop(List<XFile> files) async {
    if (files.isEmpty) return;

    final appService = ref.read(appManagementServiceProvider);

    for (final file in files) {
      final isApk = file.path.toLowerCase().endsWith('.apk');
      if (!isApk) continue;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('正在安装: ${file.name}...'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      final result = await appService.installApk(widget.deviceId, file.path);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${file.name}: ${result.isSuccess ? "安装成功" : "安装失败: ${result.message}"}',
          ),
          backgroundColor: result.isSuccess
              ? const Color(0xff09c47c)
              : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
        _scheduleAutoFit();
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

  void _scheduleAutoFit() {
    int attempts = 0;
    Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      attempts++;

      final overviewAsync = ref.read(deviceOverviewProvider(widget.deviceId));
      final resolution = overviewAsync.maybeWhen(
        data: (overview) => overview.physicalResolution,
        orElse: () => null,
      );
      double aspectRatio = _getAspectRatio(resolution);

      try {
        final size = await ScrcpyFlutter.getVideoSize(
          deviceId: widget.deviceId,
        );
        if (size != null && size['width']! > 0 && size['height']! > 0) {
          aspectRatio = size['width']! / size['height']!;
        }
      } catch (_) {}

      final renderBox =
          _viewerKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final viewerSize = renderBox.size;
        final double viewerW = viewerSize.width;
        final double viewerH = viewerSize.height;
        if (viewerW > 0 && viewerH > 0) {
          timer.cancel();
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) {
              _fitWindowToAspectRatio(aspectRatio, viewerW, viewerH);
            }
          });
          return;
        }
      }

      if (attempts >= 15) {
        timer.cancel();
      }
    });
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
            SizedBox(
              width: double.infinity,
              child: MirrorFloatingToolbar(
                deviceId: widget.deviceId,
                windowId: widget.windowId,
              ),
            ),
          Expanded(
            child: ClipRRect(
              child: Listener(
                key: _viewerKey,
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) {
                  final now = DateTime.now();
                  if (_lastPointerDownTime != null &&
                      now.difference(_lastPointerDownTime!) <
                          const Duration(milliseconds: 300)) {
                    _handleDoubleTap(e);
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
      body: DropTarget(
        onDragDone: (details) => _handleDrop(details.files),
        child: KeyboardListener(
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
                  height: 30, // 调小高度以在 macOS 上更紧凑，确保标题上下居中
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
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
                        onPressed: () => showMirrorSettingsDialog(
                          context: context,
                          ref: ref,
                          deviceId: widget.deviceId,
                          windowId: widget.windowId,
                          isAlwaysOnTop: _isAlwaysOnTop,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(child: contentWidget),
            ],
          ),
        ),
      ),
    );
  }
}
