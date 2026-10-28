part of 'app_settings_controller.dart';

/// 名称由主窗口独占写入；子窗口先请求主窗口校验传输互斥，再接收广播。
mixin HarmonyNameSettings
    on Notifier<AppSettings>, SettingsBroadcast, NotificationSettings {
  Future<void> setHarmonyShareLocalName(
    String value, {
    bool broadcast = true,
  }) async {
    ShareLocalName.validate(value);
    final preferences = await SharedPreferences.getInstance();
    if (!broadcast) {
      await _reloadHarmonyShareName(preferences);
      return;
    }
    if (ref.read(windowIdProvider).isNotEmpty) {
      await AppSettingsController._mainSettingsChannel.invokeMethod(
        'change_harmony_share_local_name',
        value,
      );
      await _reloadHarmonyShareName(preferences);
      return;
    }
    await HarmonyShareService.instance.configureLocalName(value, () async {
      await _writeHarmonyPreference(
        preferences,
        () =>
            preferences.setString(HarmonySharePreferenceKeys.localName, value),
      );
      state = state.copyWith(harmonyShareLocalName: value);
    });
    try {
      await _broadcastSettingChange('update_harmony_share_local_name', value);
    } catch (failure) {
      debugPrint('Harmony Share name broadcast failed: $failure');
    }
  }

  /// 广播是刷新信号；读取最新落盘值，避免迟到的旧广播覆盖较新的名称。
  Future<void> _reloadHarmonyShareName(SharedPreferences preferences) async {
    await preferences.reload();
    final saved = preferences.getString(HarmonySharePreferenceKeys.localName) ??
        ShareLocalName.defaultName;
    ShareLocalName.validate(saved);
    state = state.copyWith(harmonyShareLocalName: saved);
  }
}
