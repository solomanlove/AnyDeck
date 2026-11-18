part of 'embedded_scrcpy_service.dart';

/// 融合副屏的启动守护与 DPI 更新入口；状态随对应投屏会话回收。
extension EmbeddedScrcpyFusion on EmbeddedScrcpyService {
  /// 首帧已确认后结束启动期 Task 回迁守护，让手机上的主动操作生效。
  void finishAppLaunchGuard(String deviceId) {
    _sessions[deviceId]?.escapeGuardian?.cancel();
  }

  /// DPI 的能力探测、串行更新与退出还原由当前副屏会话统一管理。
  Future<bool> setFusionDisplayDensity(
    String deviceId,
    FusionDisplayGeometry geometry,
  ) {
    final session = _sessions[deviceId];
    final density = session?.displayDensity;
    if (density == null) return Future<bool>.value(false);
    return density.applyWhenResized(
      geometry: geometry,
      isCurrent: () => _sessions[deviceId] == session,
    );
  }
}
