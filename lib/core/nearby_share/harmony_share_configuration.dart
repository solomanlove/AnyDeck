part of 'harmony_share_service.dart';

/// 名称只在空闲时切换；保存失败恢复旧配置，已建立的会话不被改名。
extension _HarmonyShareConfiguration on HarmonyShareService {
  Future<void> _configureLocalName(
    String value,
    Future<void> Function() save,
  ) async {
    ShareLocalName.validate(value);
    if (busy || _configuring) throw StateError('Transfer or settings active');
    _configuring = true;
    _changed();
    try {
      await _stopWindow();
      await save();
      _localName = value;
      peers.clear();
    } finally {
      _configuring = false;
      _changed();
      if (_enabled) await _startWindow();
    }
  }
  /// 空闲时保存手动授权并重开监听，保存失败继续使用落盘的旧模式。
  Future<void> _configureDirectMode(bool value, Future<void> Function() save) async {
    if (busy || _configuring) throw StateError('Transfer or settings active');
    _configuring = true;
    _changed();
    try {
      await _stopWindow();
      await save();
      _directModeEnabled = value;
      peers.clear();
    } finally {
      _configuring = false;
      _changed();
      if (_enabled) await _startWindow();
    }
  }

}
