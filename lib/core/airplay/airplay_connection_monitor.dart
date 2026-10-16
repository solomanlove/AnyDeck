import 'airplay_server_state.dart';

/// 区分 AirPlay 流重置与持续断线；恢复 Mirroring 后立即清除断线状态。
class AirPlayConnectionMonitor {
  DateTime? _idleSince;

  bool isDisconnected(AirPlayServerStatus status, DateTime now) {
    if (status == AirPlayServerStatus.mirroring) {
      _idleSince = null;
      return false;
    }
    if (status == AirPlayServerStatus.stopped) return true;
    _idleSince ??= now;
    return now.difference(_idleSince!) >= const Duration(seconds: 3);
  }
}
