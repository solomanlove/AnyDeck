import 'package:any_deck/core/scrcpy/mirror_stream_health.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用确定的时间与接收积压验证降级边界，不依赖真实网络测速。
void main() {
  const original = MirrorVideoQuality(maxSize: 0, bitrate: 8000000);
  const slow = MirrorStreamHealth(videoLagMs: 500);
  MirrorVideoQuality? sample(
    MirrorRecoveryPolicy policy,
    int seconds, {
    MirrorVideoQuality quality = original,
    MirrorStreamHealth health = slow,
    bool wireless = true,
  }) => policy.evaluate(
    health: health,
    current: quality,
    wireless: wireless,
    elapsed: Duration(seconds: seconds),
  );

  test('连续三次积压才降档，短暂抖动与静止无数据不触发', () {
    final policy = MirrorRecoveryPolicy();
    expect(sample(policy, 1), isNull);
    expect(sample(policy, 2), isNull);
    expect(sample(policy, 3, health: const MirrorStreamHealth()), isNull);
    expect(sample(policy, 4), isNull);
    expect(sample(policy, 5), isNull);
    final next = sample(policy, 6)!;
    expect((next.maxSize, next.bitrate), (1280, 4000000));
  });

  test('持续弱网按档下降，有冷却和最低档，不反复重连', () {
    final policy = MirrorRecoveryPolicy();
    var quality = original;
    final decisions = <(int, int)>[];
    for (var i = 1; i <= 120; i++) {
      final next = sample(policy, i, quality: quality);
      if (next != null) {
        decisions.add((next.maxSize, next.bitrate));
        quality = next;
      }
    }
    expect(decisions, [(1280, 4000000), (960, 2000000), (640, 1000000)]);
  });

  test('冷却期间不累积坏样本，USB 不降画质', () {
    final policy = MirrorRecoveryPolicy();
    for (var i = 1; i <= 10; i++) {
      expect(sample(policy, i, wireless: false), isNull);
    }
    sample(policy, 11);
    sample(policy, 12);
    final next = sample(policy, 13)!;
    for (var i = 14; i < 35; i++) {
      expect(sample(policy, i, quality: next), isNull);
    }
    expect(sample(policy, 35, quality: next)?.bitrate, 2000000);
  });

  test('用户原有低参数不被提高', () {
    final policy = MirrorRecoveryPolicy();
    const low = MirrorVideoQuality(maxSize: 480, bitrate: 500000);
    for (var i = 1; i <= 10; i++) {
      expect(sample(policy, i, quality: low), isNull);
    }
    final capped = const MirrorVideoQuality(
      maxSize: 720,
      bitrate: 8000000,
    ).cappedBy(const MirrorVideoQuality(maxSize: 1280, bitrate: 4000000));
    expect((capped.maxSize, capped.bitrate), (720, 4000000));
    // 音频恢复携带原始尺寸 0 时，仍遵守用户后来收紧的尺寸上限。
    expect(low.cappedBy(original).maxSize, 480);
  });

  test('音频意外退出在 USB 也恢复，但有重试上限和冷却', () {
    final policy = MirrorRecoveryPolicy();
    const failed = MirrorStreamHealth(audioFailed: true);
    expect(sample(policy, 1, health: failed, wireless: false), original);
    expect(sample(policy, 2, health: failed, wireless: false), isNull);
    expect(sample(policy, 21, health: failed, wireless: false), original);
    expect(sample(policy, 41, health: failed, wireless: false), isNull);
  });

  test('原生 packed 健康快照保留音频状态和延迟', () {
    final health = MirrorStreamHealth.fromNative((1 << 32) | 480);
    expect(health.audioFailed, isTrue);
    expect(health.videoLagMs, 480);
    expect(MirrorStreamHealth.fromNative(0).audioFailed, isFalse);
  });
}
