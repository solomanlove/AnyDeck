part of 'dlna_renderer_service.dart';

/// DLNA SOAP 控制动作与播放器路由。
extension DlnaRendererControl on DlnaRendererService {
  Future<Map<String, String>?> _dispatch(
    String action,
    String body, {
    String? userAgent,
  }) async {
    switch (action) {
      case 'SetAVTransportURI':
        final raw = DlnaProtocol.element(body, 'CurrentURI')?.trim();
        final uri = raw == null ? null : Uri.tryParse(raw);
        if (uri == null ||
            !['http', 'https'].contains(uri.scheme) ||
            uri.host.isEmpty) {
          return null;
        }
        _stopWindowTimer?.cancel();
        _stopWindowTimer = null;
        debugPrint('[DLNA] media scheme=${uri.scheme} host=${uri.host}');
        _mediaGeneration++;
        _dashSource =
            uri.path.toLowerCase().endsWith('.mpd') ||
            body.toLowerCase().contains('application/dash+xml');
        _currentUrl = raw;
        _currentMetadata =
            DlnaProtocol.element(body, 'CurrentURIMetaData') ?? '';
        _transportState = 'STOPPED';
        _playbackError = null;
        final generation = _mediaGeneration;
        debugPrint('[DLNA] source accepted generation=$generation');
        await _resetPlayers(keepWindow: true);
        if (generation != _mediaGeneration) return {};
        // 鸿蒙版 B 站的 Platinum 控制端只轮询状态，不发送 Play。
        _pendingPlatinumPlayGeneration =
            userAgent?.contains('Platinum/1.0.5.13') == true
            ? generation
            : null;
        _notifyControlChange();
        unawaited(_notifySubscribers());
        return {};
      case 'Play':
        _pendingPlatinumPlayGeneration = null;
        final generation = _mediaGeneration;
        await _playerReset;
        if (generation != _mediaGeneration) return {};
        if (_currentUrl == null) return null;
        _playbackError = null;
        _stopWindowTimer?.cancel();
        _stopWindowTimer = null;
        if (_transportState == 'PAUSED_PLAYBACK') {
          if (_fallback.isActive) {
            await _fallback.invoke<bool>('dlnaPlay');
          } else {
            await DlnaRendererService._player.invokeMethod<void>('play');
          }
        } else if (_dashSource ||
            Uri.parse(_currentUrl!).path.toLowerCase().endsWith('.flv') ||
            _currentMetadata.toLowerCase().contains('video/x-flv')) {
          _transportState = 'PLAYING';
          unawaited(
            _openFallback(
              'Media requires libmpv',
              generation: generation,
              stopNative: false,
            ),
          );
        } else {
          await DlnaRendererService._player.invokeMethod<void>('playUrl', {
            'url': _currentUrl,
            'generation': generation,
            'loadingText': _loadingText,
            'alwaysOnTop': _alwaysOnTop,
          });
          await _fallback.stop();
        }
        if (generation != _mediaGeneration) return {};
        debugPrint('[DLNA] play accepted generation=$generation');
        _transportState = 'PLAYING';
        _notifyControlChange();
        unawaited(_notifySubscribers());
        return {};
      case 'Pause':
        _pendingPlatinumPlayGeneration = null;
        if (_fallback.isActive) {
          await _fallback.invoke<bool>('dlnaPause');
        } else {
          await DlnaRendererService._player.invokeMethod<void>('pause');
        }
        _transportState = 'PAUSED_PLAYBACK';
        _notifyControlChange();
        unawaited(_notifySubscribers());
        return {};
      case 'Stop':
        _pendingPlatinumPlayGeneration = null;
        _stopWindowTimer?.cancel();
        _mediaGeneration++;
        if (_currentUrl == null) {
          _transportState = 'NO_MEDIA_PRESENT';
          _notifyControlChange();
          return {};
        }
        _transportState = 'STOPPED';
        final generation = _mediaGeneration;
        debugPrint('[DLNA] stop accepted generation=$generation');
        await _resetPlayers(keepWindow: true);
        if (generation == _mediaGeneration && _transportState == 'STOPPED') {
          // 抖音切视频也会发送 Stop，短暂等待后再判定投屏真正结束。
          _stopWindowTimer = Timer(_stopWindowDelay, () {
            if (generation == _mediaGeneration &&
                _transportState == 'STOPPED') {
              unawaited(() async {
                try {
                  await _resetPlayers(
                    keepWindow: false,
                    expectedGeneration: generation,
                  );
                } catch (error) {
                  debugPrint('[DLNA] close after Stop failed: $error');
                } finally {
                  if (generation == _mediaGeneration) _endMediaSession();
                }
              }());
            }
          });
        }
        _notifyControlChange();
        unawaited(_notifySubscribers());
        return {};
      case 'Seek':
        final target = DlnaProtocol.element(body, 'Target');
        final seconds = target == null ? null : DlnaProtocol.parseTime(target);
        if (seconds == null) return null;
        if (_fallback.isActive) {
          await _fallback.invoke<bool>('dlnaSeek', seconds);
        } else {
          await DlnaRendererService._player.invokeMethod<void>('seek', seconds);
        }
        return {};
      case 'GetTransportInfo':
        if (_pendingPlatinumPlayGeneration == _mediaGeneration &&
            _currentUrl != null &&
            _transportState == 'STOPPED') {
          _pendingPlatinumPlayGeneration = null;
          debugPrint(
            '[DLNA] Platinum controller requested playback status; starting media',
          );
          await _dispatch('Play', '');
        }
        return {
          'CurrentTransportState': _transportState,
          'CurrentTransportStatus': _playbackError == null ? 'OK' : 'ERROR_OCCURRED',
          'CurrentSpeed': '1',
        };
      case 'GetPositionInfo':
        final seconds = await _readPosition();
        final duration = await _readDuration();
        return {
          'Track': _currentUrl == null ? '0' : '1',
          'TrackDuration': DlnaProtocol.formatTime(duration),
          'TrackMetaData': _currentMetadata,
          'TrackURI': _currentUrl ?? '',
          'RelTime': DlnaProtocol.formatTime(seconds),
          'AbsTime': DlnaProtocol.formatTime(seconds),
          'RelCount': '0',
          'AbsCount': '0',
        };
      case 'GetMediaInfo':
        return {
          'NrTracks': _currentUrl == null ? '0' : '1',
          'MediaDuration': DlnaProtocol.formatTime(await _readDuration()),
          'CurrentURI': _currentUrl ?? '',
          'CurrentURIMetaData': _currentMetadata,
          'NextURI': '',
          'NextURIMetaData': '',
          'PlayMedium': 'NETWORK',
          'RecordMedium': 'NOT_IMPLEMENTED',
          'WriteStatus': 'NOT_IMPLEMENTED',
        };
      case 'GetDeviceCapabilities':
        return {
          'PlayMedia': 'NETWORK',
          'RecMedia': 'NOT_IMPLEMENTED',
          'RecQualityModes': 'NOT_IMPLEMENTED',
        };
      case 'GetTransportSettings':
        return {'PlayMode': 'NORMAL', 'RecQualityMode': 'NOT_IMPLEMENTED'};
      case 'GetProtocolInfo':
        return {'Source': '', 'Sink': DlnaProtocol.sinkProtocolInfo};
      case 'GetCurrentConnectionIDs':
        return {'ConnectionIDs': '0'};
      case 'GetCurrentConnectionInfo':
        return {
          'RcsID': '0',
          'AVTransportID': '0',
          'ProtocolInfo': _dashSource
              ? 'http-get:*:application/dash+xml:*'
              : 'http-get:*:video/mp4:*',
          'PeerConnectionManager': '',
          'PeerConnectionID': '-1',
          'Direction': 'Input',
          'Status': 'OK',
        };
      case 'SetVolume':
        final volume = int.tryParse(
          DlnaProtocol.element(body, 'DesiredVolume') ?? '',
        );
        if (volume == null) return null;
        final value = volume.clamp(0, 100) / 100;
        await DlnaRendererService._player.invokeMethod<void>(
          'setVolume',
          value,
        );
        if (_fallback.isActive) {
          await _fallback.invoke<bool>('dlnaSetVolume', value);
        }
        return {};
      case 'GetVolume':
        final volume = await _readVolume();
        return {'CurrentVolume': '${(volume * 100).round()}'};
      case 'SetMute':
        final mute = DlnaProtocol.element(body, 'DesiredMute');
        if (mute != '0' && mute != '1') return null;
        await DlnaRendererService._player.invokeMethod<void>(
          'setMute',
          mute == '1',
        );
        if (_fallback.isActive) {
          await _fallback.invoke<bool>('dlnaSetMute', mute == '1');
        }
        return {};
      case 'GetMute':
        final muted = _fallback.isActive
            ? await _fallback.invoke<bool>('dlnaGetMute') ?? false
            : await DlnaRendererService._player.invokeMethod<bool>('getMute') ??
                  false;
        return {'CurrentMute': muted ? '1' : '0'};
      default:
        return null;
    }
  }

  Future<double> _readPosition() async => _fallback.isActive
      ? (await _fallback.invoke<num>('dlnaPosition'))?.toDouble() ?? 0
      : DlnaPlayerBridge.readNumber('position');

  Future<double> _readDuration() async => _fallback.isActive
      ? (await _fallback.invoke<num>('dlnaDuration'))?.toDouble() ?? 0
      : DlnaPlayerBridge.readNumber('duration');

  Future<double> _readVolume() async => _fallback.isActive
      ? (await _fallback.invoke<num>('dlnaGetVolume'))?.toDouble() ?? 1
      : DlnaPlayerBridge.readNumber('getVolume', fallback: 1);
}
