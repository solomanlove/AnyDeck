/// 面向用户的 scrcpy 启动选项，可转换为 CLI 参数。
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

  /// 为单台设备构建 scrcpy 参数列表。
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
