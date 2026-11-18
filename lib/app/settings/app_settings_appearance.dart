part of 'app_settings_controller.dart';

/// 管理明暗模式与主题主色，沿用应用设置的持久化及跨窗口广播。
mixin AppearanceSettings
    on Notifier<AppSettings>, SettingsBroadcast, ReceiverNameSettings {
  /// 更新当前主题模式，并持久化到下次启动。
  Future<void> setThemeMode(
    ThemeMode themeMode, {
    bool broadcast = true,
  }) async {
    state = state.copyWith(themeMode: themeMode);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      AppSettingsController._themeModeKey,
      themeMode.name,
    );
    await _syncVideoWindowAppearance(themeMode);
    if (broadcast) {
      try {
        await _broadcastSettingChange('update_themeMode', themeMode.name);
      } catch (e) {
        debugPrint('Failed to broadcast theme mode change: $e');
      }
    }
  }

  /// 等待初始设置读取后更新主色，避免启动加载覆盖用户刚选择的颜色。
  Future<void> setThemeColor(
    AppThemeColor themeColor, {
    bool broadcast = true,
  }) async {
    await _settingsLoaded;
    if (!ref.mounted) return;
    state = state.copyWith(themeColor: themeColor);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      AppSettingsController._themeColorKey,
      themeColor.name,
    );
    if (!ref.mounted || !broadcast) return;
    try {
      await _broadcastSettingChange('update_theme_color', themeColor.name);
    } catch (error) {
      debugPrint('Failed to broadcast theme color change: $error');
    }
  }

  /// 广播接收端只更新内存，避免再次写入较旧值或循环广播。
  Future<void> _receiveThemeColor(Object? value) async {
    if (value is! String ||
        !AppThemeColor.values.any((color) => color.name == value)) {
      return;
    }
    await _settingsLoaded;
    if (!ref.mounted) return;
    state = state.copyWith(themeColor: AppThemeColor.fromName(value));
  }
}
