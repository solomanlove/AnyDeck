import 'package:flutter/material.dart';

import '../../core/nearby_share/share_local_name.dart';

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
  static const defaultAirplayServerName = 'AnyDeck-AirPlay';
  static const defaultDlnaServerName = 'AnyDeck-DLNA';
  static const _legacyDlnaServerName = 'AnyDeck DLNA';

  /// 统一 DLNA 默认名称，同时保留用户设置的自定义名称。
  static String normalizeDlnaServerName(String? value) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty || clean == _legacyDlnaServerName
        ? defaultDlnaServerName
        : clean;
  }

  const AppSettings({
    this.language = AppLanguage.zh,
    this.themeMode = ThemeMode.system,
    this.scrcpyAlwaysOnTop = true,
    this.mirrorControlsAlwaysVisible = false,
    this.mirrorVideoBitrate = 8000000,
    this.mirrorMaxSize = 1080,
    this.mirrorAudioEnabled = true,
    this.iosMirrorAudioEnabled = true,
    this.airplayServerName = defaultAirplayServerName,
    this.dlnaServerName = defaultDlnaServerName,
    this.screenshotSavePath = '',
    this.autoIdentifyForegroundApp = false,
    this.autoIdentifyInterval = 3,
    this.forceHostRecording = false,
    this.autoPowerOffScreen = false,
    this.deviceConnectNotification = true,
    this.notificationBodyPreview = true,
    this.harmonyShareNotifications = true,
    this.harmonyShareReceiveDirectory = '',
    this.harmonyShareLocalName = ShareLocalName.defaultName,
    this.launchAtStartup = false,
    this.showWindowShortcutKey = '1',
    this.developerModeEnabled = false,
  });

  final AppLanguage language;
  final ThemeMode themeMode;
  final bool scrcpyAlwaysOnTop;
  final bool mirrorControlsAlwaysVisible;
  final int mirrorVideoBitrate;
  final int mirrorMaxSize;
  final bool mirrorAudioEnabled;
  final bool iosMirrorAudioEnabled;
  final String airplayServerName;
  final String dlnaServerName;
  final String screenshotSavePath;
  final bool autoIdentifyForegroundApp;
  final int autoIdentifyInterval;
  final bool forceHostRecording;
  final bool autoPowerOffScreen;
  final bool deviceConnectNotification;
  final bool notificationBodyPreview;
  /// 鸿蒙互联通知独立开关；系统权限仍需用户授权。
  final bool harmonyShareNotifications;
  /// 空字符串表示 Downloads，传输时创建独立子目录。
  final String harmonyShareReceiveDirectory;
  /// 新会话使用的本机名称，与 Core 的 UTF-8 长度规则保持一致。
  final String harmonyShareLocalName;
  final bool launchAtStartup;
  /// 显示主窗口的快捷键字符（默认 '1'，即 ⌘1）
  final String showWindowShortcutKey;
  /// 是否已开启开发者选项
  final bool developerModeEnabled;

  /// 创建新的不可变设置对象，未指定字段沿用当前值。
  AppSettings copyWith({
    AppLanguage? language,
    ThemeMode? themeMode,
    bool? scrcpyAlwaysOnTop,
    bool? mirrorControlsAlwaysVisible,
    int? mirrorVideoBitrate,
    int? mirrorMaxSize,
    bool? mirrorAudioEnabled,
    bool? iosMirrorAudioEnabled,
    String? airplayServerName,
    String? dlnaServerName,
    String? screenshotSavePath,
    bool? autoIdentifyForegroundApp,
    int? autoIdentifyInterval,
    bool? forceHostRecording,
    bool? autoPowerOffScreen,
    bool? deviceConnectNotification,
    bool? notificationBodyPreview,
    bool? harmonyShareNotifications,
    String? harmonyShareReceiveDirectory,
    String? harmonyShareLocalName,
    bool? launchAtStartup,
    String? showWindowShortcutKey,
    bool? developerModeEnabled,
  }) {
    return AppSettings(
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
      scrcpyAlwaysOnTop: scrcpyAlwaysOnTop ?? this.scrcpyAlwaysOnTop,
      mirrorControlsAlwaysVisible:
          mirrorControlsAlwaysVisible ?? this.mirrorControlsAlwaysVisible,
      mirrorVideoBitrate: mirrorVideoBitrate ?? this.mirrorVideoBitrate,
      mirrorMaxSize: mirrorMaxSize ?? this.mirrorMaxSize,
      mirrorAudioEnabled: mirrorAudioEnabled ?? this.mirrorAudioEnabled,
      iosMirrorAudioEnabled:
          iosMirrorAudioEnabled ?? this.iosMirrorAudioEnabled,
      airplayServerName: airplayServerName ?? this.airplayServerName,
      dlnaServerName: dlnaServerName ?? this.dlnaServerName,
      screenshotSavePath: screenshotSavePath ?? this.screenshotSavePath,
      autoIdentifyForegroundApp: autoIdentifyForegroundApp ?? this.autoIdentifyForegroundApp,
      autoIdentifyInterval: autoIdentifyInterval ?? this.autoIdentifyInterval,
      forceHostRecording: forceHostRecording ?? this.forceHostRecording,
      autoPowerOffScreen: autoPowerOffScreen ?? this.autoPowerOffScreen,
      deviceConnectNotification: deviceConnectNotification ?? this.deviceConnectNotification,
      notificationBodyPreview: notificationBodyPreview ?? this.notificationBodyPreview,
      harmonyShareNotifications: harmonyShareNotifications ?? this.harmonyShareNotifications,
      harmonyShareReceiveDirectory: harmonyShareReceiveDirectory ?? this.harmonyShareReceiveDirectory,
      harmonyShareLocalName: harmonyShareLocalName ?? this.harmonyShareLocalName,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      showWindowShortcutKey: showWindowShortcutKey ?? this.showWindowShortcutKey,
      developerModeEnabled: developerModeEnabled ?? this.developerModeEnabled,
    );
  }
}
