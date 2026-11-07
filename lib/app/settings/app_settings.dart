import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/nearby_share/share_local_name.dart';
import '../shortcuts/mirror_shortcut.dart';
import '../shortcuts/window_shortcut.dart';

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
    this.harmonyShareDirectMode = false,
    this.launchAtStartup = false,
    this.showWindowShortcutKey = '1',
    this.mainWindowShortcut,
    this.windowShortcuts = const WindowShortcutSettings(),
    this.mirrorShortcuts = const MirrorShortcutSettings(),
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
  /// 手动允许连接手机 WLAN；默认关闭，使用现有 LAN 链路。
  final bool harmonyShareDirectMode;
  final bool launchAtStartup;
  /// 显示主窗口的快捷键字符（默认 '1'，即 ⌘1）
  final String showWindowShortcutKey;
  /// 完整主窗口快捷键；缺失时兼容旧的单字符设置。
  final KeyboardShortcutBinding? mainWindowShortcut;
  /// 关闭窗口、打开设置和退出软件的完整组合键。
  final WindowShortcutSettings windowShortcuts;
  KeyboardShortcutBinding get mainWindowBinding {
    if (mainWindowShortcut != null) return mainWindowShortcut!;
    final legacyKey = showWindowShortcutKey.isEmpty
        ? '1'
        : showWindowShortcutKey[0].toLowerCase();
    return KeyboardShortcutBinding.primary(
      LogicalKeyboardKey(legacyKey.codeUnitAt(0)),
    );
  }
  /// 投屏操作的按键覆盖项，未覆盖时使用目录中的默认组合键。
  final MirrorShortcutSettings mirrorShortcuts;
  /// 是否已开启开发者选项
  final bool developerModeEnabled;

  /// 按实际作用范围检查组合冲突：通用操作同时覆盖主窗口和投屏窗口。
  String? shortcutConflict(
    KeyboardShortcutBinding binding, {
    WindowShortcut? windowAction,
    MirrorShortcut? mirrorAction,
  }) {
    if (!binding.isEnabled) return null;
    for (final action in WindowShortcut.values) {
      if (action != windowAction && windowShortcuts.bindingFor(action) == binding) {
        return action.labelKey;
      }
    }
    if (windowAction != null && mainWindowBinding == binding) {
      return 'mainWindowShortcut';
    }
    if (windowAction != null || mirrorAction != null) {
      for (final action in MirrorShortcut.values) {
        if (action != mirrorAction && mirrorShortcuts.bindingFor(action) == binding) {
          return action.labelKey;
        }
      }
    }
    return null;
  }

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
    bool? harmonyShareDirectMode,
    bool? launchAtStartup,
    String? showWindowShortcutKey,
    KeyboardShortcutBinding? mainWindowShortcut,
    WindowShortcutSettings? windowShortcuts,
    MirrorShortcutSettings? mirrorShortcuts,
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
      harmonyShareDirectMode: harmonyShareDirectMode ?? this.harmonyShareDirectMode,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      showWindowShortcutKey: showWindowShortcutKey ?? this.showWindowShortcutKey,
      mainWindowShortcut: mainWindowShortcut ?? this.mainWindowShortcut,
      windowShortcuts: windowShortcuts ?? this.windowShortcuts,
      mirrorShortcuts: mirrorShortcuts ?? this.mirrorShortcuts,
      developerModeEnabled: developerModeEnabled ?? this.developerModeEnabled,
    );
  }
}
