import 'app_settings.dart';

/// Android scrcpy 画质预设；maxSize 为最长边像素数，bitrate 为视频目标码率。
enum MirrorQualityPreset {
  smooth(2000000, 720, 'mirrorPresetSmooth'),
  balanced(8000000, 1080, 'mirrorPresetBalanced'),
  clear(16000000, 1920, 'mirrorPresetClear');

  const MirrorQualityPreset(this.bitrate, this.maxSize, this.labelKey);
  final int bitrate;
  final int maxSize;
  final String labelKey;

  static MirrorQualityPreset? matching(AppSettings settings) {
    for (final preset in values) {
      if (settings.mirrorVideoBitrate == preset.bitrate &&
          settings.mirrorMaxSize == preset.maxSize) {
        return preset;
      }
    }
    return null;
  }
}
