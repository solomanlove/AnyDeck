part of 'embedded_scrcpy_service.dart';

/// 健康采样和自动恢复复用现有会话启停流程；不改变全局画质偏好。
extension _EmbeddedMirrorRecovery on ActiveEmbeddedMirrorNotifier {
  void _watchStreamHealth(
    EmbeddedScrcpyService service,
    int textureId,
    String? newDisplay,
    String? startApp,
  ) {
    _healthTimer?.cancel();
    final generation = _generation;
    _healthTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isRecoveryCurrent(generation, textureId)) {
        timer.cancel();
        return;
      }
      if (_recovering || _starting != null || _stopping != null) return;
      final health = service.getStreamHealth(deviceId);
      final current = service.getVideoQuality(deviceId);
      if (health == null || current == null) return;
      final quality = _recoveryPolicy.evaluate(
        health: health,
        current: current,
        wireless:
            MirrorTransportType.fromDeviceId(deviceId) !=
            MirrorTransportType.usb,
        elapsed: _healthClock.elapsed,
      );
      if (quality == null) return;
      AppLogRecorder.instance.record(
        'stream_recovery_requested texture=$textureId '
        'video_lag_ms=${health.videoLagMs} audio_failed=${health.audioFailed} '
        'max_size=${quality.maxSize} bitrate=${quality.bitrate}',
        tag: 'mirror',
        level: 'W',
      );
      unawaited(_recoverStream(service, quality, newDisplay, startApp));
    });
  }

  Future<void> _recoverStream(
    EmbeddedScrcpyService service,
    MirrorVideoQuality quality,
    String? newDisplay,
    String? startApp,
  ) async {
    _recovering = true;
    final stopping = _stop(resetRecovery: false);
    final generation = _generation;
    try {
      await stopping;
      // 关闭窗口、手动刷新或换线优先，迟到的恢复不得重新拉起旧通道。
      if (!_isRecoveryCurrent(generation)) return;
      await _start(newDisplay, startApp, service.isMuted(deviceId), quality);
    } catch (error) {
      // _startOnce 已发出断线事件，由窗口沿用同机选路/重连机制。
      AppLogRecorder.instance.record(
        'stream_recovery_failed: $error',
        tag: 'mirror',
        level: 'E',
      );
    } finally {
      _recovering = false;
    }
  }
}
