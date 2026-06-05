import 'package:flutter/material.dart';

/// 本地字符串表支持的用户可选语言。
enum AppLanguage {
  zh('zh'),
  en('en');

  const AppLanguage(this.code);

  final String code;

  /// MaterialApp 使用的 Locale。
  Locale get locale => Locale(code);

  /// 当本地存储缺失或无法识别时，默认回退到中文。
  static AppLanguage fromCode(String? code) {
    return code == AppLanguage.en.code ? AppLanguage.en : AppLanguage.zh;
  }
}

/// 可持久化的应用级设置，控制语言和外观。
class AppSettings {
  const AppSettings({
    this.language = AppLanguage.zh,
    this.themeMode = ThemeMode.system,
    this.scrcpyAlwaysOnTop = true,
    this.mirrorVideoBitrate = 8000000,
    this.mirrorMaxSize = 1080,
    this.mirrorAudioEnabled = true,
    this.screenshotSavePath = '',
  });

  final AppLanguage language;
  final ThemeMode themeMode;
  final bool scrcpyAlwaysOnTop;
  final int mirrorVideoBitrate;
  final int mirrorMaxSize;
  final bool mirrorAudioEnabled;
  final String screenshotSavePath;

  /// 创建新的不可变设置对象，未指定字段沿用当前值。
  AppSettings copyWith({
    AppLanguage? language,
    ThemeMode? themeMode,
    bool? scrcpyAlwaysOnTop,
    int? mirrorVideoBitrate,
    int? mirrorMaxSize,
    bool? mirrorAudioEnabled,
    String? screenshotSavePath,
  }) {
    return AppSettings(
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
      scrcpyAlwaysOnTop: scrcpyAlwaysOnTop ?? this.scrcpyAlwaysOnTop,
      mirrorVideoBitrate: mirrorVideoBitrate ?? this.mirrorVideoBitrate,
      mirrorMaxSize: mirrorMaxSize ?? this.mirrorMaxSize,
      mirrorAudioEnabled: mirrorAudioEnabled ?? this.mirrorAudioEnabled,
      screenshotSavePath: screenshotSavePath ?? this.screenshotSavePath,
    );
  }
}
