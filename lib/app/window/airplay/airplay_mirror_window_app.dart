import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/airplay/airplay_server_service.dart';
import '../../../core/airplay/airplay_server_state.dart';
import '../../l10n/app_localizations.dart';
import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../window_close_shortcut.dart';

/// AirPlay 投屏独立子窗口入口。
class AirPlayMirrorWindowApp extends ConsumerWidget {
  const AirPlayMirrorWindowApp({
    super.key,
    required this.windowId,
    required this.argument,
  });

  final String windowId;
  final Map<String, dynamic> argument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final deviceName = argument['deviceName'] as String? ?? 'iPhone';
    final handle = (argument['handle'] as num?)?.toInt() ?? 0x416972506c617931;
    final initialRatio = (argument['aspectRatio'] as num?)?.toDouble() ?? (9.0 / 19.5);

    return MaterialApp(
      onGenerateTitle: (context) => '$deviceName - AirPlay',
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
      home: WindowCloseShortcut(
        child: AirPlayMirrorWindowContent(
          windowId: windowId,
          handle: handle,
          deviceName: deviceName,
          initialAspectRatio: initialRatio,
        ),
      ),
    );
  }
}

/// AirPlay 投屏窗口核心内容组件。
///
/// 具备以下特性：
/// 1. 窗口等比缩放保护 (windowManager.setAspectRatio)；
/// 2. 自动检测 iPhone 画面旋转（横屏/竖屏）并自适应调整窗口长宽比；
/// 3. 支持鼠标悬停展示毛玻璃快捷工具栏（置顶、全屏、等比重置、分辨率指示）；
/// 4. 手机端主动断开时优雅提示。
class AirPlayMirrorWindowContent extends ConsumerStatefulWidget {
  const AirPlayMirrorWindowContent({
    super.key,
    required this.windowId,
    required this.handle,
    required this.deviceName,
    required this.initialAspectRatio,
  });

  final String windowId;
  final int handle;
  final String deviceName;
  final double initialAspectRatio;

  @override
  ConsumerState<AirPlayMirrorWindowContent> createState() =>
      _AirPlayMirrorWindowContentState();
}

class _AirPlayMirrorWindowContentState extends ConsumerState<AirPlayMirrorWindowContent>
    with WindowListener {
  static const _channel = MethodChannel('anydeck/rust_texture');

  int? _textureId;
  bool _isLoading = true;
  bool _isDisconnected = false;
  bool _isAlwaysOnTop = false;
  bool _isFullScreen = false;
  bool _isToolbarHovered = false;

  late double _aspectRatio;
  Size? _videoSize;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _aspectRatio = widget.initialAspectRatio;
    windowManager.addListener(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initWindow();
      _registerTexture();
      _startStatusPolling();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    windowManager.removeListener(this);
    if (_textureId != null) {
      unawaited(_channel.invokeMethod<void>('unregister', {'textureId': _textureId}));
    }
    super.dispose();
  }

  /// 初始化窗口约束与等比缩放
  Future<void> _initWindow() async {
    try {
      await windowManager.setMinimumSize(const Size(240, 360));
      await windowManager.setAspectRatio(_aspectRatio);
      final isTop = ref.read(appSettingsProvider).scrcpyAlwaysOnTop;
      _isAlwaysOnTop = isTop;
      await windowManager.setAlwaysOnTop(isTop);
    } catch (e) {
      debugPrint('[AirPlayWindow] Init window failed: $e');
    }
  }

  /// 注册当前子窗口的 Flutter External Texture
  Future<void> _registerTexture() async {
    try {
      final id = await _channel.invokeMethod<int>('register', {
        'handle': widget.handle,
      });
      if (mounted) {
        setState(() {
          _textureId = id;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[AirPlayWindow] Failed to register texture: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 轮询检测分辨率与连接状态
  void _startStatusPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      if (!mounted) return;
      final service = AirPlayServerService.instance;
      final status = service.getStatus(widget.handle);
      final size = service.getDimensions(widget.handle);

      if (status == AirPlayServerStatus.stopped || status == AirPlayServerStatus.idle) {
        if (!_isDisconnected && mounted) {
          setState(() => _isDisconnected = true);
        }
        return;
      }

      if (size != null && size.width > 0 && size.height > 0) {
        final newRatio = size.width / size.height;
        final hasSizeChanged = _videoSize == null ||
            _videoSize!.width != size.width ||
            _videoSize!.height != size.height;

        if (hasSizeChanged || (newRatio - _aspectRatio).abs() > 0.02) {
          _videoSize = size;
          _aspectRatio = newRatio;
          if (mounted) {
            setState(() {
              _isDisconnected = false;
            });
          }
          // 同步窗口锁定比例
          await windowManager.setAspectRatio(newRatio);
        }
      }
    });
  }

  /// 切换窗口置顶
  Future<void> _toggleAlwaysOnTop() async {
    final nextState = !_isAlwaysOnTop;
    setState(() => _isAlwaysOnTop = nextState);
    await windowManager.setAlwaysOnTop(nextState);
  }

  /// 切换全屏状态
  Future<void> _toggleFullScreen() async {
    final willFull = !_isFullScreen;
    setState(() => _isFullScreen = willFull);
    await windowManager.setFullScreen(willFull);
  }

  /// 恢复自适应标准尺寸
  Future<void> _resetWindowSize() async {
    final currentBounds = await windowManager.getBounds();
    final double targetWidth = _aspectRatio < 1.0 ? 360.0 : 720.0;
    final double targetHeight = targetWidth / _aspectRatio;
    await windowManager.setBounds(
      Rect.fromLTWH(
        currentBounds.left,
        currentBounds.top,
        targetWidth,
        targetHeight,
      ),
    );
    await windowManager.setAspectRatio(_aspectRatio);
  }

  // ==================== WindowListener ====================

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullScreen = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_isFullScreen) _toggleFullScreen();
          },
        },
        child: Focus(
          autofocus: true,
          child: MouseRegion(
            onEnter: (_) => setState(() => _isToolbarHovered = true),
            onExit: (_) => setState(() => _isToolbarHovered = false),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 核心渲染区
                Center(
                  child: _buildVideoContent(context, isDark),
                ),

                // 顶部悬浮毛玻璃工具栏
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    opacity: (_isToolbarHovered && !_isFullScreen) ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: IgnorePointer(
                      ignoring: !_isToolbarHovered || _isFullScreen,
                      child: _buildFloatingToolbar(context, isDark),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建视频流或状态占位视图
  Widget _buildVideoContent(BuildContext context, bool isDark) {
    if (_isDisconnected) {
      return Container(
        color: isDark ? const Color(0xff1e1e1e) : const Color(0xfff5f5f7),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.airplay_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.t('airplayDisconnected'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => windowManager.close(),
              icon: const Icon(CupertinoIcons.xmark, size: 16),
              label: Text(context.l10n.t('airplayCloseWindow')),
            ),
          ],
        ),
      );
    }

    if (_isLoading || _textureId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              context.l10n.t('airplayBroadcasting').replaceAll('{name}', widget.deviceName),
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return AspectRatio(
      aspectRatio: _aspectRatio,
      child: Texture(textureId: _textureId!),
    );
  }

  /// 顶部轻量浮动操作栏
  Widget _buildFloatingToolbar(BuildContext context, bool isDark) {
    final resolutionStr = _videoSize != null
        ? '${_videoSize!.width.toInt()} × ${_videoSize!.height.toInt()}'
        : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.75),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Icon(
              CupertinoIcons.device_phone_portrait,
              size: 16,
              color: Colors.white.withValues(alpha: 0.9),
            ),
            const SizedBox(width: 8),
            Text(
              widget.deviceName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (resolutionStr.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  resolutionStr,
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                ),
              ),
            ],
            const Spacer(),
            // 置顶按钮
            _WindowIconButton(
              icon: _isAlwaysOnTop
                  ? CupertinoIcons.pin_fill
                  : CupertinoIcons.pin,
              tooltip: context.l10n.t('airplayAlwaysOnTop'),
              color: _isAlwaysOnTop ? Theme.of(context).colorScheme.primary : Colors.white70,
              onPressed: _toggleAlwaysOnTop,
            ),
            const SizedBox(width: 4),
            // 等比自适应缩放按钮
            _WindowIconButton(
              icon: CupertinoIcons.arrow_up_left_arrow_down_right,
              tooltip: context.l10n.t('airplayResetAspect'),
              color: Colors.white70,
              onPressed: _resetWindowSize,
            ),
            const SizedBox(width: 4),
            // 全屏按钮
            _WindowIconButton(
              icon: _isFullScreen
                  ? CupertinoIcons.fullscreen_exit
                  : CupertinoIcons.fullscreen,
              tooltip: _isFullScreen
                  ? context.l10n.t('airplayExitFullscreen')
                  : context.l10n.t('airplayFullscreen'),
              color: Colors.white70,
              onPressed: _toggleFullScreen,
            ),
            const SizedBox(width: 4),
            // 关闭窗口按钮
            _WindowIconButton(
              icon: CupertinoIcons.xmark,
              tooltip: context.l10n.t('airplayCloseWindow'),
              color: Colors.white70,
              onPressed: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部小图标按钮
class _WindowIconButton extends StatelessWidget {
  const _WindowIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}
