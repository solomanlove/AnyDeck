import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/airplay/airplay_server_service.dart';
import '../../../core/airplay/airplay_connection_monitor.dart';
import '../../../core/airplay/airplay_server_state.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../multi_window_compat.dart';
import '../desktop_window_title_service.dart';
import 'mirror_immersive_overlay.dart';
import 'mirror_session_status_bar.dart';
import 'mirror_window_frame_adapter.dart';

/// 在通用 iOS 投屏窗口内渲染 AirPlay Texture，并复用 USB 窗口的窗口操作。
class IosAirPlayMirrorContent extends StatefulWidget {
  const IosAirPlayMirrorContent({
    super.key,
    required this.handle,
    required this.deviceName,
    required this.initialAspectRatio,
    required this.autoHideControls,
    required this.toolbar,
    required this.onDisconnected,
    required this.isAlwaysOnTop,
    required this.onToggleAlwaysOnTop,
    this.isFullScreen = false,
    this.onToggleFullScreen,
  });

  final int handle;
  final String deviceName;
  final double initialAspectRatio;
  final bool autoHideControls;
  final Widget toolbar;
  final VoidCallback onDisconnected;
  /// 与 USB 共用控制器的置顶状态，避免 AirPlay 自行初始化为 false。
  final bool isAlwaysOnTop;
  final VoidCallback onToggleAlwaysOnTop;
  final bool isFullScreen;
  final VoidCallback? onToggleFullScreen;

  @override
  State<IosAirPlayMirrorContent> createState() =>
      _IosAirPlayMirrorContentState();
}

class _IosAirPlayMirrorContentState extends State<IosAirPlayMirrorContent>
    with WindowListener {
  static const _textureChannel = MethodChannel('anydeck/rust_texture');
  static const _windowChannel = MethodChannel('any_deck/window');

  final GlobalKey _viewerKey = GlobalKey();
  Timer? _pollTimer;
  Timer? _resizeSettleTimer;
  int? _textureId;
  Size? _videoSize;
  late double _aspectRatio;
  bool _isDisconnected = false;
  bool _isFullScreen = false;
  bool _isFittingWindow = false;
  bool _hasMirrored = false;
  bool _reportedDisconnect = false;
  AirPlayConnectionMonitor _connectionMonitor = AirPlayConnectionMonitor();

  bool get _effectiveFullScreen => widget.isFullScreen || _isFullScreen;

  @override
  void initState() {
    super.initState();
    _aspectRatio = widget.initialAspectRatio;
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _registerTexture();
      _startPolling();
      await _fitWindowToVideo();
    });
  }

  /// 本地化标题同时同步系统窗口标题，便于在 Dock / 窗口菜单区分投屏类型。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(DesktopWindowTitleService.setTitle(
      '${widget.deviceName} · ${context.l10n.t('iosMirrorWifiAirPlay')}',
    ));
  }

  @override
  void didUpdateWidget(covariant IosAirPlayMirrorContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.handle != widget.handle) {
      unawaited(_replaceTexture());
    }
    if (oldWidget.isFullScreen && !widget.isFullScreen) {
      _isFullScreen = false;
      unawaited(_fitWindowToVideo());
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _pollTimer?.cancel();
    _resizeSettleTimer?.cancel();
    final textureId = _textureId;
    if (textureId != null) {
      unawaited(
        _textureChannel.invokeMethod<void>('unregister', {
          'textureId': textureId,
        }),
      );
    }
    super.dispose();
  }

  @override
  void onWindowLeaveFullScreen() {
    if (_isFullScreen) {
      setState(() => _isFullScreen = false);
    }
    unawaited(_fitWindowToVideo());
  }

  @override
  void onWindowResized() {
    if (_effectiveFullScreen || _isFittingWindow) return;
    _resizeSettleTimer?.cancel();
    _resizeSettleTimer = Timer(const Duration(milliseconds: 80), () {
      if (mounted && !_effectiveFullScreen) {
        unawaited(_fitWindowToVideo());
      }
    });
  }

  Future<void> _replaceTexture() async {
    _pollTimer?.cancel();
    final previous = _textureId;
    _textureId = null;
    _videoSize = null;
    _isDisconnected = false;
    _hasMirrored = false;
    _reportedDisconnect = false;
    _connectionMonitor = AirPlayConnectionMonitor();
    if (mounted) setState(() {});
    if (previous != null) {
      await _textureChannel.invokeMethod<void>('unregister', {
        'textureId': previous,
      });
    }
    await _registerTexture();
    _startPolling();
  }

  Future<void> _registerTexture() async {
    try {
      final textureId = await _textureChannel.invokeMethod<int>('register', {
        'handle': widget.handle,
      });
      if (!mounted) return;
      setState(() => _textureId = textureId);
    } catch (error) {
      debugPrint('[AirPlayWindow] Texture registration failed: $error');
      if (mounted) setState(() => _isDisconnected = true);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      if (!mounted) return;
      final service = AirPlayServerService.instance;
      final status = service.getStatus(widget.handle);
      final size = service.getDimensions(widget.handle);
      final disconnected = _connectionMonitor.isDisconnected(status, DateTime.now());
      if (status != AirPlayServerStatus.mirroring) {
        if (!disconnected) return;
        if (!_isDisconnected) {
          debugPrint('[AirPlayWindow] Disconnected: status=$status, '
              'error=${service.getLastError(widget.handle)}');
          setState(() => _isDisconnected = true);
        }
        if (_hasMirrored && !_reportedDisconnect) {
          _reportedDisconnect = true;
          widget.onDisconnected();
        }
        return;
      }
      if (!_hasMirrored) setState(() => _hasMirrored = true);
      _reportedDisconnect = false;
      if (_isDisconnected) setState(() => _isDisconnected = false);
      if (size == null || size.width <= 0 || size.height <= 0) return;
      final nextRatio = size.width / size.height;
      final changed =
          _videoSize != size || (nextRatio - _aspectRatio).abs() > 0.002;
      if (!changed) return;
      _videoSize = size;
      _aspectRatio = nextRatio;
      setState(() => _isDisconnected = false);
      await _fitWindowToVideo();
    });
  }

  Future<void> _fitWindowToVideo() async {
    if (_effectiveFullScreen || _isFittingWindow || _aspectRatio <= 0) return;
    _isFittingWindow = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted || _effectiveFullScreen) return;
      final viewer = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
      if (viewer == null || viewer.size.isEmpty) return;
      await windowManager.setAspectRatio(0);
      await MirrorWindowFrameAdapter.fitWindowToAspectRatio(
        windowChannel: _windowChannel,
        aspectRatio: _aspectRatio,
        viewerW: viewer.size.width,
        viewerH: viewer.size.height,
      );
      final frame = await MirrorWindowFrameAdapter.getWindowFrame(_windowChannel);
      final width = (frame != null && frame.width > 0)
          ? frame.width
          : (await windowManager.getBounds()).width;
      final viewerWidth = width - mirrorWindowSideChromeWidth;
      if (viewerWidth > 0) {
        final targetHeight =
            viewerWidth / _aspectRatio + mirrorWindowTopChromeHeight;
        await windowManager.setAspectRatio(width / targetHeight);
      }
    } finally {
      _isFittingWindow = false;
    }
  }

  Future<void> _toggleFullScreen() async {
    if (widget.onToggleFullScreen != null) {
      widget.onToggleFullScreen!();
      return;
    }
    final next = !_isFullScreen;
    if (next) {
      await windowManager.setAspectRatio(0);
    }
    try {
      await _windowChannel.invokeMethod('setFullScreen', next);
    } on MissingPluginException {
      await windowManager.setFullScreen(next);
    }
    if (mounted) setState(() => _isFullScreen = next);
    if (!next) {
      unawaited(_fitWindowToVideo());
    }
  }

  Future<void> _stopAirPlay() async {
    await AirPlayServerService.instance.disconnect(widget.handle);
    if (!mounted) return;
    setState(() => _isDisconnected = true);
    if (!_reportedDisconnect) {
      _reportedDisconnect = true;
      widget.onDisconnected();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLiveMirrorVisible = _textureId != null && _hasMirrored && !_isDisconnected;
    final windowBackground = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xff121212)
        : const Color(0xfff8f9fa);

    return Scaffold(
      backgroundColor: isLiveMirrorVisible
          ? Colors.transparent
          : windowBackground,
      body: MirrorImmersiveOverlay(
        autoHide: isLiveMirrorVisible && widget.autoHideControls,
        viewer: SizedBox.expand(key: _viewerKey, child: _buildVideo(context)),
        titleBar: DragToMoveArea(
          child: Container(
            height: 30,
            padding: EdgeInsets.only(
              left: defaultTargetPlatform == TargetPlatform.macOS ? 80 : 16,
              right: 4,
            ),
            decoration: BoxDecoration(
              color: windowBackground,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.deviceName} · ${context.l10n.t('iosMirrorWifiAirPlay')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontSize: 16),
                  ),
                ),
                if (isLiveMirrorVisible)
                  const MirrorSessionDuration(),
                ..._windowActions(context),
              ],
            ),
          ),
        ),
        toolbar: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      widget.toolbar,
                    ],
                  ),
                ),
              ),
              MirrorSessionFps(
                deviceId: '',
                isIos: false,
                isHarmony: false,
                airplayHandle: widget.handle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 窗口操作固定在标题栏，避免混入手机控制工具栏。
  List<Widget> _windowActions(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final toolbarFg = Theme.of(context).appColors.toolbarForeground;
    return [
      for (final action in [
        (
          widget.isAlwaysOnTop ? CupertinoIcons.pin_fill : CupertinoIcons.pin,
          'airplayAlwaysOnTop',
          widget.onToggleAlwaysOnTop,
          widget.isAlwaysOnTop ? Colors.orange : toolbarFg,
        ),
        (
          _effectiveFullScreen
              ? CupertinoIcons.fullscreen_exit
              : CupertinoIcons.fullscreen,
          'airplayFullscreen',
          _toggleFullScreen,
          toolbarFg,
        ),
        (
          CupertinoIcons.stop_circle,
          'airplayStopSession',
          _stopAirPlay,
          colors.error,
        ),
      ])
        IconButton(
          icon: Icon(action.$1, size: 16, color: action.$4),
          tooltip: context.l10n.t(action.$2),
          onPressed: action.$3,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          visualDensity: VisualDensity.compact,
        ),
    ];
  }

  Widget _buildVideo(BuildContext context) {
    if (_isDisconnected) {
      return Center(
        child: Text(
          context.l10n.t('airplayDisconnected'),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    if (_textureId == null || !_hasMirrored) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(context.l10n.t('airplayMirrorWaitingFrame')),
          ],
        ),
      );
    }
    final safeRatio = _aspectRatio > 0 ? _aspectRatio : (9.0 / 19.5);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: safeRatio,
          child: Texture(textureId: _textureId!),
        ),
      ),
    );
  }
}
