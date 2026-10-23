part of 'dlna_renderer_service.dart';

/// DLNA 名称更新独立于播放器生命周期，改名时保留正在播放的媒体。
extension DlnaRendererName on DlnaRendererService {
  String get serverName => _serverName;

  Future<void> setServerName(String value) async {
    final name = value.trim().isEmpty ? DlnaProtocol.serverName : value.trim();
    if (_serverName == name) return;
    if (isRunning) await _advertise(alive: false);
    _serverName = name;
    try {
      await DlnaRendererService._player.invokeMethod<void>('setTitle', name);
    } catch (error) {
      debugPrint('[DLNA] player title update failed: $error');
    }
    if (isRunning) await _advertise(alive: true);
    _notifyNameChange();
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
