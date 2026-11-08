part of 'dlna_renderer_service.dart';

/// 播放器回退与媒体错误隔离；失败不关闭 DLNA 发现和控制服务。
extension DlnaRendererPlayback on DlnaRendererService {
  /// AVPlayer 报错后只对当前仍在播放的媒体执行一次 libmpv 回退。
  Future<void> _handleNativeFailure(String detail, int generation) async {
    debugPrint('[DLNA] AVPlayer failed: $detail');
    await _openFallback(detail, generation: generation, stopNative: true);
  }

  Future<void> _openFallback(
    String detail, {
    required int generation,
    required bool stopNative,
  }) async {
    while (true) {
      final pending = _fallbackOperation;
      if (pending == null) break;
      await pending;
    }
    final url = _currentUrl;
    if (generation != _mediaGeneration ||
        url == null ||
        _transportState != 'PLAYING') {
      return;
    }
    if (_fallback.isActive) return;
    final operation = Completer<void>();
    _fallbackOperation = operation.future;
    try {
      final volume = await DlnaPlayerBridge.readNumber(
        'getVolume',
        fallback: 1,
      );
      final muted =
          await DlnaRendererService._player.invokeMethod<bool>('getMute') ??
          false;
      if (stopNative) {
        await DlnaRendererService._player.invokeMethod<void>(
          'prepare',
          _loadingText,
        );
      }
      debugPrint('[DLNA] starting libmpv fallback');
      final opened = await _fallback.open(
        url,
        title: _serverName,
        loadingText: _loadingText,
        volume: volume,
        muted: muted,
        alwaysOnTop: _alwaysOnTop,
      );
      if (_mediaGeneration != generation || _transportState != 'PLAYING') {
        await _fallback.stop();
        return;
      }
      if (!opened) {
        _transportState = 'STOPPED';
        _playbackError = '$detail; libmpv could not render a video frame';
      } else {
        await DlnaRendererService._player.invokeMethod<void>('stop');
        _playbackError = null;
        debugPrint('[DLNA] libmpv fallback playing');
      }
    } catch (error) {
      if (_mediaGeneration != generation) return;
      _playbackError = detail;
      _transportState = 'STOPPED';
      debugPrint('[DLNA] libmpv fallback exception: $error');
    } finally {
      _fallbackOperation = null;
      operation.complete();
      _notifyControlChange();
      unawaited(_notifySubscribers());
    }
  }
}
