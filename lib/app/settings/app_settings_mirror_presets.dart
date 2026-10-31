part of 'app_settings_controller.dart';

/// 一次更新预设的两个参数，沿用现有持久化键与跨窗口消息，不重启活动投屏。
mixin MirrorPresetSettings on Notifier<AppSettings>, SettingsBroadcast {
  Future<void> setMirrorQualityPreset(MirrorQualityPreset preset) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(
      AppSettingsController._mirrorVideoBitrateKey,
      preset.bitrate,
    );
    await preferences.setInt(
      AppSettingsController._mirrorMaxSizeKey,
      preset.maxSize,
    );
    if (!ref.mounted) return;
    state = state.copyWith(
      mirrorVideoBitrate: preset.bitrate,
      mirrorMaxSize: preset.maxSize,
    );
    for (final entry in {
      'update_video_bitrate': preset.bitrate,
      'update_max_size': preset.maxSize,
    }.entries) {
      try {
        await _broadcastSettingChange(entry.key, entry.value);
      } catch (error) {
        debugPrint('Failed to broadcast mirror preset: $error');
      }
    }
  }
}
