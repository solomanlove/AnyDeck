import 'dart:math' as math;

/// 原生接收线程的低频快照；lag 是相对接收积压，并非网络测速或 FPS。
class MirrorStreamHealth {
  const MirrorStreamHealth({this.videoLagMs = 0, this.audioFailed = false});

  factory MirrorStreamHealth.fromNative(int value) => MirrorStreamHealth(
    videoLagMs: value & 0xffffffff,
    audioFailed: (value & (1 << 32)) != 0,
  );

  final int videoLagMs;
  final bool audioFailed;
}

/// 仅本次会话生效的编码上限；maxSize 为最长边，0 表示原始尺寸。
class MirrorVideoQuality {
  const MirrorVideoQuality({required this.maxSize, required this.bitrate});

  final int maxSize;
  final int bitrate;

  MirrorVideoQuality cappedBy(MirrorVideoQuality limit) => MirrorVideoQuality(
    maxSize: maxSize == 0
        ? limit.maxSize
        : limit.maxSize == 0
        ? maxSize
        : math.min(maxSize, limit.maxSize),
    bitrate: math.min(bitrate, limit.bitrate),
  );
}

/// 恢复决策与生命周期分离；持续积压才降档，间隔 20 秒避免无线抖动重连风暴。
class MirrorRecoveryPolicy {
  static const _levels = [
    MirrorVideoQuality(maxSize: 1280, bitrate: 4000000),
    MirrorVideoQuality(maxSize: 960, bitrate: 2000000),
    MirrorVideoQuality(maxSize: 640, bitrate: 1000000),
  ];
  int _level = 0;
  int _badSamples = 0;
  int _audioRestarts = 0;
  Duration _nextRecovery = Duration.zero;

  /// 返回 null 表示继续当前会话；返回参数表示用该画质重建音视频。
  MirrorVideoQuality? evaluate({
    required MirrorStreamHealth health,
    required MirrorVideoQuality current,
    required bool wireless,
    required Duration elapsed,
  }) {
    if (elapsed < _nextRecovery) {
      _badSamples = 0;
      return null;
    }
    _badSamples = wireless && health.videoLagMs >= 350
        ? math.min(_badSamples + 1, 3)
        : 0;
    MirrorVideoQuality? quality;
    if (_badSamples >= 3) {
      // 用户本来选择低码率/低分辨率时，不能因自动降档反向提高任何参数。
      while (_level < _levels.length) {
        final next = current.cappedBy(_levels[_level++]);
        if (next.maxSize != current.maxSize ||
            next.bitrate != current.bitrate) {
          quality = next;
          break;
        }
      }
    }
    // 已正常工作后断开的音频流最多自动重建两次；不支持采集不触发此状态。
    if (health.audioFailed && _audioRestarts < 2) {
      _audioRestarts++;
      quality ??= current;
    }
    if (quality != null) {
      _badSamples = 0;
      _nextRecovery = elapsed + const Duration(seconds: 20);
    }
    return quality;
  }
}
