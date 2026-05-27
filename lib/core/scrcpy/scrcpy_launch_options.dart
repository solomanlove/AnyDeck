class ScrcpyLaunchOptions {
  const ScrcpyLaunchOptions({
    this.maxSize = 1920,
    this.videoBitRate = '8M',
    this.maxFps,
    this.alwaysOnTop = false,
  });

  final int maxSize;
  final String videoBitRate;
  final int? maxFps;
  final bool alwaysOnTop;

  List<String> toArgs(String deviceId) {
    return [
      '-s',
      deviceId,
      '--max-size',
      maxSize.toString(),
      '--video-bit-rate',
      videoBitRate,
      if (maxFps != null) ...['--max-fps', maxFps.toString()],
      if (alwaysOnTop) '--always-on-top',
    ];
  }
}
