part of 'dlna_renderer_service.dart';

/// DLNA 名称更新独立于播放器生命周期，改名时保留正在播放的媒体。
extension DlnaRendererName on DlnaRendererService {
  String get serverName => _serverName;

  Future<void> setServerName(String value) async {
    final name = value.trim().isEmpty ? DlnaProtocol.serverName : value.trim();
    if (_baseServerName != name) {
      _baseServerName = name;
      _nameGeneration++;
      _nameMonitor?.updateName(name);
    }
    await _changePublishedName(name, _nameGeneration);
  }

  /// 广播改名串行执行；播放器标题更新失败也必须公布新名并通知 UI。
  Future<void> _changePublishedName(String name, int generation) {
    final previous = _nameChange;
    final changing = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      if (generation != _nameGeneration || _serverName == name) return;
      if (isRunning) await _advertise(alive: false);
      if (generation != _nameGeneration) return;
      _serverName = name;
      try {
        await DlnaRendererService._player.invokeMethod<void>('setTitle', name);
      } catch (error) {
        debugPrint('[DLNA] player title update failed: $error');
      }
      if (_fallback.hasWindow) {
        try {
          await _fallback.setTitle(name);
        } catch (error) {
          debugPrint('[DLNA] fallback title update failed: $error');
        }
      }
      if (generation != _nameGeneration) return;
      if (isRunning) await _advertise(alive: true);
      _notifyNameChange();
    }();
    _nameChange = changing;
    return changing.whenComplete(() {
      if (identical(_nameChange, changing)) _nameChange = null;
    });
  }
}

/// 控制端的事件订阅与有效期状态。
class _DlnaSubscription {
  _DlnaSubscription(this.callback, this.path);

  final Uri callback;
  final String path;
  DateTime expires = DateTime.now().add(const Duration(minutes: 5));
  int sequence = 0;
}
