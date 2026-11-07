part of 'harmony_share_service.dart';

/// Core 必须确认实际发现已就绪，启动挂起或失败时不把进程存活当作正在搜索。
extension _HarmonyShareDiscoveryState on HarmonyShareService {
  void _clearDiscoveryStartup() {
    _discoveryStartTimer?.cancel();
    _discoveryStartTimer = null;
  }

  void _watchDiscoveryStartup(ShareCoreReceiveSession receiver) {
    _clearDiscoveryStartup();
    _discoveryStartTimer = Timer(const Duration(seconds: 8), () {
      _discoveryStartTimer = null;
      if (_receiver != receiver || !_enabled || _discoveryReady || busy) return;
      error = 'receive_failed: discovery_start_timeout';
      _discoveryReady = false;
      peers.clear();
      _changed();
      unawaited(_stopWindow());
    });
  }
}
