import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

/// 通过 SharedPreferences 持久化的应用设置 Riverpod 状态。
final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

/// 负责加载和保存设置，并通过乐观更新保持 UI 响应。
class AppSettingsController extends Notifier<AppSettings> {
  static const _languageKey = 'settings.language';
  static const _themeModeKey = 'settings.themeMode';

  @override
  AppSettings build() {
    // 先返回默认设置，SharedPreferences 读取完成后再覆盖真实值。
    _load();
    return const AppSettings();
  }

  /// 更新当前语言，并持久化到下次启动。
  Future<void> setLanguage(AppLanguage language) async {
    state = state.copyWith(language: language);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_languageKey, language.code);
  }

  /// 更新当前主题模式，并持久化到下次启动。
  Future<void> setThemeMode(ThemeMode themeMode) async {
    state = state.copyWith(themeMode: themeMode);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themeModeKey, themeMode.name);
  }

  /// 从本地读取设置，缺失字段使用安全默认值。
  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final language = AppLanguage.fromCode(preferences.getString(_languageKey));
    final themeMode = _themeModeFromName(preferences.getString(_themeModeKey));
    state = AppSettings(language: language, themeMode: themeMode);
  }

  /// 将本地存储的枚举名称映射回 Flutter 的 ThemeMode。
  ThemeMode _themeModeFromName(String? name) {
    return switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}
