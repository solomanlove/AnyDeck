import 'airplay_server_state.dart';

/// 按镜像会话协调开窗：首帧前即可打开，失败退避重试，同一连接只打开一次。
/// [open] 返回窗口是否已显示；HTTP 视频和音频不进入此协调器。
class AirPlayMirrorWindowCoordinator {
  AirPlayMirrorWindowCoordinator({required this.open});

  final Future<bool> Function(AirPlaySessionData) open;
  final Map<int, _MirrorOpening> _sessions = {};

  void reconcile(AirPlaySessionData? root, DateTime now) {
    final active = root?.mirroringSessions ?? const <AirPlaySessionData>[];
    final ids = active.map((session) => session.id).toSet();
    _sessions.removeWhere((id, _) => !ids.contains(id));
    for (final session in active) {
      var entry = _sessions[session.id];
      if (entry == null || entry.clientId != session.clientDeviceId) {
        entry = _MirrorOpening(session.clientDeviceId);
        _sessions[session.id] = entry;
      }
      if (entry.opened || entry.pending || now.isBefore(entry.retryAt)) {
        continue;
      }
      entry.pending = true;
      _open(session, entry, now);
    }
  }

  Future<void> _open(
    AirPlaySessionData session,
    _MirrorOpening entry,
    DateTime now,
  ) async {
    try {
      entry.opened = await open(session);
    } catch (_) {
      entry.opened = false;
    } finally {
      entry.pending = false;
      entry.retryAt = now.add(const Duration(seconds: 3));
    }
  }

  void clear() => _sessions.clear();
}

class _MirrorOpening {
  _MirrorOpening(this.clientId);
  final String? clientId;
  bool opened = false;
  bool pending = false;
  DateTime retryAt = DateTime.fromMillisecondsSinceEpoch(0);
}
