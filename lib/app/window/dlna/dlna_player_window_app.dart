import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../multi_window_compat.dart';
import '../sub_window_method_dispatcher.dart';
import '../window_close_shortcut.dart';

/// DLNA 的 libmpv 回退窗口；主窗口仍负责 UPnP 协议和播放状态。
///
/// [windowId] 用于把关闭和失败事件关联到当前子窗口。仅由多窗口入口创建，
/// 媒体 URL 通过 `dlnaOpen` 通道传入，不能放在窗口启动参数中。
class DlnaPlayerWindowApp extends StatefulWidget {
  const DlnaPlayerWindowApp({super.key, required this.windowId});

  final String windowId;

  @override
  State<DlnaPlayerWindowApp> createState() => _DlnaPlayerWindowAppState();
}

class _DlnaPlayerWindowAppState extends State<DlnaPlayerWindowApp>
    with WindowListener {
  static const _events = WindowMethodChannel(
    'any_deck/dlna_fallback_events',
    mode: ChannelMode.unidirectional,
  );
  late final Player _player;
  late final VideoController _video;
  StreamSubscription<String>? _errorSubscription;
  bool _closing = false;
  bool _opening = false;
  bool _loading = true;
  bool _renderedFrame = false;
  bool _muted = false;
  double _volume = 1;
  String _loadingText = '';
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _video = VideoController(_player);
    _errorSubscription = _player.stream.error.listen((error) {
      _lastError = _safeError(error);
      debugPrint('[DLNA] libmpv error: $_lastError');
      if (!_opening && !_closing) {
        unawaited(_notify('failed', _lastError).then((_) => _close(notify: false)));
      }
    });
    windowManager.addListener(this);
    unawaited(windowManager.setPreventClose(true));
    SubWindowMethodDispatcher.registerHandler(_handleCall);
  }

  /// 不记录媒体地址、签名参数或播放器返回的完整 URL。
  String _safeError(String message) => message.replaceAll(
    RegExp(r'https?://[^\s"\x27<>]+', caseSensitive: false),
    '[media URL]',
  );

  Future<void> _notify(String method, [String? detail]) async {
    try {
      await _events.invokeMethod<void>(method, {
        'windowId': widget.windowId,
        'detail': ?detail,
      });
    } catch (error) {
      debugPrint('[DLNA] fallback notification failed: $error');
    }
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    if (_closing) return null;
    switch (call.method) {
      case 'dlnaOpen':
        final args = call.arguments;
        if (args is! Map) return false;
        final raw = args['url'];
        final uri = raw is String ? Uri.tryParse(raw) : null;
        if (uri == null ||
            !['http', 'https'].contains(uri.scheme) ||
            uri.host.isEmpty) {
          return false;
        }
        _opening = true;
        _lastError = null;
        if (mounted) {
          setState(() {
            _loading = true;
            _loadingText = args['loadingText'] as String? ?? '';
          });
        }
        try {
          final title = args['title'];
          if (title is String && title.isNotEmpty) {
            await windowManager.setTitle(title);
          }
          _volume = ((args['volume'] as num?)?.toDouble() ?? 1).clamp(0, 1);
          _muted = args['muted'] == true;
          await _player.setVolume(_muted ? 0 : _volume * 100);
          await _player.open(Media(raw));
          // media_kit_video 的首帧 Future 只完成一次；复用窗口时改等新媒体进度。
          if (_renderedFrame) {
            if (_player.state.position <= Duration.zero) {
              await _player.stream.position
                  .firstWhere((position) => position > Duration.zero)
                  .timeout(const Duration(seconds: 18));
            }
          } else {
            await _video.waitUntilFirstFrameRendered.timeout(
              const Duration(seconds: 18),
            );
          }
          if (_lastError != null || _closing) return false;
          await showCurrentAdbManageSubWindow();
          _renderedFrame = true;
          if (mounted) setState(() => _loading = false);
          debugPrint('[DLNA] libmpv first frame rendered');
          return true;
        } catch (error) {
          debugPrint('[DLNA] libmpv open failed: ${_safeError('$error')}');
          return false;
        } finally {
          _opening = false;
        }
      case 'dlnaPrepare':
        _opening = true;
        if (mounted) setState(() => _loading = true);
        try {
          await _player.stop();
        } finally {
          _opening = false;
        }
        return true;
      case 'dlnaSetLoadingText':
        final text = call.arguments;
        if (text is! String) return false;
        if (mounted) setState(() => _loadingText = text);
        return true;
      case 'dlnaPlay':
        await _player.play();
        return true;
      case 'dlnaPause':
        await _player.pause();
        return true;
      case 'dlnaSeek':
        final seconds = (call.arguments as num?)?.toDouble();
        if (seconds == null || !seconds.isFinite || seconds < 0) return false;
        await _player.seek(Duration(milliseconds: (seconds * 1000).round()));
        return true;
      case 'dlnaPosition':
        return _player.state.position.inMilliseconds / 1000;
      case 'dlnaDuration':
        return _player.state.duration.inMilliseconds / 1000;
      case 'dlnaSetVolume':
        final volume = (call.arguments as num?)?.toDouble();
        if (volume == null || !volume.isFinite) return false;
        _volume = volume.clamp(0, 1);
        await _player.setVolume(_muted ? 0 : _volume * 100);
        return true;
      case 'dlnaGetVolume':
        return _volume;
      case 'dlnaSetMute':
        if (call.arguments is! bool) return false;
        _muted = call.arguments == true;
        await _player.setVolume(_muted ? 0 : _volume * 100);
        return true;
      case 'dlnaGetMute':
        return _muted;
      case 'dlnaSetTitle':
        final title = call.arguments;
        if (title is! String || title.isEmpty) return false;
        await windowManager.setTitle(title);
        return true;
      case 'dlnaStop':
        await _close(notify: false);
        return true;
    }
    return null;
  }

  Future<void> _close({required bool notify}) async {
    if (_closing) return;
    _closing = true;
    try {
      if (notify) await _notify('stopped');
      await _player.stop();
    } finally {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
  }

  @override
  void onWindowClose() => unawaited(_close(notify: true));

  @override
  void dispose() {
    SubWindowMethodDispatcher.removeHandler(_handleCall);
    windowManager.removeListener(this);
    unawaited(_errorSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: WindowCloseShortcut(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: _video,
              fit: BoxFit.contain,
              fill: Colors.black,
              controls: (_) => const SizedBox.shrink(),
            ),
            if (_loading)
              ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      if (_loadingText.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          _loadingText,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
