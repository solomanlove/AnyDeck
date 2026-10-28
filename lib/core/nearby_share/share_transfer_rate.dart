/// 当前批次的瞬时估算；不持久化、不根据文件数量推测单文件进度。
class ShareRateEstimate {
  const ShareRateEstimate(this.bytesPerSecond, this.remaining);
  final double bytesPerSecond;
  final Duration remaining;
}

/// 使用单调时钟和近 5 秒真实字节样本；准备/等待确认和长时间停顿不产生估算。
class ShareTransferRate {
  ShareTransferRate({Duration Function()? elapsed}) {
    final watch = Stopwatch()..start();
    _elapsed = elapsed ?? (() => watch.elapsed);
  }
  late final Duration Function() _elapsed;
  final _samples = <({Duration at, int bytes})>[];
  int _total = 0;
  Duration _bucketAt = Duration.zero;
  static const staleAfter = Duration(seconds: 3);

  void reset() {
    _samples.clear();
    _total = 0;
  }

  void observe(int bytes, int total) {
    if (total < 1 || bytes < 0 || bytes > total) return;
    final now = _elapsed();
    if (_samples.isNotEmpty &&
        (total != _total ||
            bytes < _samples.last.bytes ||
            now < _samples.last.at)) {
      return;
    }
    if (_samples.isNotEmpty && now - _samples.last.at > staleAfter) {
      _samples.clear();
    }
    _total = total;
    if (_samples.length > 1 &&
        now - _bucketAt < const Duration(milliseconds: 250)) {
      _samples[_samples.length - 1] = (at: now, bytes: bytes);
    } else {
      _samples.add((at: now, bytes: bytes));
      _bucketAt = now;
    }
    while (_samples.length > 2 &&
        now - _samples[1].at > const Duration(seconds: 5)) {
      _samples.removeAt(0);
    }
    if (_samples.length > 32) _samples.removeAt(0);
  }

  ShareRateEstimate? get estimate {
    if (_samples.length < 2) return null;
    final first = _samples.first;
    final last = _samples.last;
    final now = _elapsed();
    final micros = (last.at - first.at).inMicroseconds;
    if (now < last.at ||
        now - last.at > staleAfter ||
        micros < 500000 ||
        last.bytes >= _total) {
      return null;
    }
    final rate = (last.bytes - first.bytes) * 1000000 / micros;
    if (rate <= 0 || !rate.isFinite) return null;
    return ShareRateEstimate(
      rate,
      Duration(seconds: ((_total - last.bytes) / rate).ceil()),
    );
  }
}
