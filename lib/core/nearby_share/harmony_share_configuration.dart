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
}
