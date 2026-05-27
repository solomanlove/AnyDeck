import 'package:flutter/material.dart';

enum AppLanguage {
  zh('zh'),
  en('en');

  const AppLanguage(this.code);

  final String code;

  Locale get locale => Locale(code);

  static AppLanguage fromCode(String? code) {
    return code == AppLanguage.en.code ? AppLanguage.en : AppLanguage.zh;
  }
}

class AppSettings {
  const AppSettings({
    this.language = AppLanguage.zh,
    this.themeMode = ThemeMode.system,
  });

  final AppLanguage language;
  final ThemeMode themeMode;

  AppSettings copyWith({AppLanguage? language, ThemeMode? themeMode}) {
    return AppSettings(
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}
