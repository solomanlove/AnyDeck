import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/airplay/airplay_server_service.dart';
import '../../../core/airplay/airplay_server_state.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../multi_window_compat.dart';
import 'mirror_toolbar_button.dart';
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
  });

  final int handle;
  final String deviceName;
  final double initialAspectRatio;
  final bool autoHideControls;
  final Widget toolbar;
  final VoidCallback onDisconnected;

  @override
  State<IosAirPlayMirrorContent> createState() =>
      _IosAirPlayMirrorContentState();
}

class _IosAirPlayMirrorContentState extends State<IosAirPlayMirrorContent> {
  static const _textureChannel = MethodChannel('anydeck/rust_texture');
  static const _windowChannel = MethodChannel('adb_manage/window');

  final GlobalKey _viewerKey = GlobalKey();
  Timer? _pollTimer;
  int? _textureId;
  Size? _videoSize;
  late double _aspectRatio;
  bool _isDisconnected = false;
  bool _isAlwaysOnTop = false;
  bool _isFullScreen = false;
  bool _hasMirrored = false;
  bool _reportedDisconnect = false;

  @override
  void initState() {
    super.initState();
    _aspectRatio = widget.initialAspectRatio;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _registerTexture();
      _startPolling();
    });
  }

  @override
  void didUpdateWidget(covariant IosAirPlayMirrorContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.handle != widget.handle) {
      unawaited(_replaceTexture());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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

  Future<void> _replaceTexture() async {
    _pollTimer?.cancel();
    final previous = _textureId;
    _textureId = null;
    _videoSize = null;
    _isDisconnected = false;
    _hasMirrored = false;
    _reportedDisconnect = false;
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
      if (status != AirPlayServerStatus.mirroring) {
        if (!_isDisconnected) setState(() => _isDisconnected = true);
        if (_hasMirrored && !_reportedDisconnect) {
          _reportedDisconnect = true;
          widget.onDisconnected();
        }
        return;
      }
      _hasMirrored = true;
      _reportedDisconnect = false;
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
    if (_isFullScreen) return;
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final viewer = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewer == null || viewer.size.isEmpty) return;
    await windowManager.setAspectRatio(0);
    await MirrorWindowFrameAdapter.fitWindowToAspectRatio(
      windowChannel: _windowChannel,
      aspectRatio: _aspectRatio,
      viewerW: viewer.size.width,
      viewerH: viewer.size.height,
    );
    final bounds = await windowManager.getBounds();
    final viewerWidth = bounds.width - mirrorWindowSideChromeWidth;
    final targetHeight =
        viewerWidth / _aspectRatio + mirrorWindowTopChromeHeight;
    await windowManager.setAspectRatio(bounds.width / targetHeight);
  }

  Future<void> _toggleAlwaysOnTop() async {
    final next = !_isAlwaysOnTop;
    await windowManager.setAlwaysOnTop(next);
    if (mounted) setState(() => _isAlwaysOnTop = next);
  }

  Future<void> _toggleFullScreen() async {
    final next = !_isFullScreen;
    await windowManager.setFullScreen(next);
    if (mounted) setState(() => _isFullScreen = next);
  }

  Future<void> _stopAirPlay() async {
    await AirPlayServerService.instance.stop(
      AirPlaySessionData(
        id: widget.handle,
        serverName: widget.deviceName,
        rtspPort: 7000,
        videoPort: 7100,
        status: AirPlayServerStatus.stopped,
      ),
    );
    if (!mounted) return;
    setState(() => _isDisconnected = true);
    if (!_reportedDisconnect) {
      _reportedDisconnect = true;
      widget.onDisconnected();
    }
  }

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).appColors.toolbarForeground;
    final resolution = _videoSize == null
        ? ''
        : '${_videoSize!.width.toInt()} × ${_videoSize!.height.toInt()}';
    final isLiveMirrorVisible = _textureId != null && !_isDisconnected;
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
        titleBar: _isFullScreen
            ? const SizedBox.shrink()
            : DragToMoveArea(
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
                    Flexible(
                      child: Text(
                        '${widget.deviceName} · ${context.l10n.t('iosMirrorWifiAirPlay')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (resolution.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        resolution,
                        style: TextStyle(fontSize: 11, color: foreground),
                      ),
                    ],
                    const Spacer(),
                    if (isLiveMirrorVisible)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: MirrorSessionDuration(),
                      ),
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
                      MirrorToolbarButton(
                        icon: Icon(_isAlwaysOnTop ? CupertinoIcons.pin_fill : CupertinoIcons.pin,
                          color: _isAlwaysOnTop ? Colors.orange : foreground, size: 16),
                        tooltip: context.l10n.t('airplayAlwaysOnTop'),
                        onPressed: _toggleAlwaysOnTop,
                      ),
                      MirrorToolbarButton(
                        icon: Icon(CupertinoIcons.arrow_up_left_arrow_down_right, color: foreground, size: 16),
                        tooltip: context.l10n.t('airplayResetAspect'),
                        onPressed: _fitWindowToVideo,
                      ),
                      MirrorToolbarButton(
                        icon: Icon(CupertinoIcons.fullscreen, color: foreground, size: 16),
                        tooltip: context.l10n.t('airplayFullscreen'),
                        onPressed: _toggleFullScreen,
                      ),
                      MirrorToolbarButton(
                        icon: const Icon(CupertinoIcons.stop_circle, color: Colors.redAccent, size: 16),
                        tooltip: context.l10n.t('airplayStopSession'),
                        onPressed: _stopAirPlay,
                      ),
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

  Widget _buildVideo(BuildContext context) {
    if (_isDisconnected) {
      return Center(
        child: Text(
          context.l10n.t('airplayDisconnected'),
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    if (_textureId == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SizedBox.expand(child: Texture(textureId: _textureId!));
  }
}
