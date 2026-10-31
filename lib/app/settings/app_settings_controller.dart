import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'mirror_quality_preset.dart';
import 'harmony_share_preference_keys.dart';
import '../../core/nearby_share/share_receive_directory.dart';
import '../../core/nearby_share/share_local_name.dart';
import '../../core/nearby_share/harmony_share_service.dart';
import 'desktop_autostart_service.dart';
import '../../core/airplay/airplay_server_service.dart';
import '../../core/dlna/dlna_renderer_service.dart';
import '../../core/ios/ios_usb_mirror_service.dart';
import '../window/desktop_window_title_service.dart';
import '../window/desktop_window_manager_service.dart';
import '../window/sub_window_method_dispatcher.dart';

part 'app_settings_broadcast.dart';
part 'app_settings_mirror_presets.dart';
part 'app_settings_notifications.dart';
part 'app_settings_harmony_name.dart';

/// 全局唯一的窗口 ID Provider，主窗口默认为空字符串。
final windowIdProvider = Provider<String>((ref) => '');

/// 通过 SharedPreferences 持久化的应用设置 Riverpod 状态。
final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

/// 负责加载和保存设置，并通过乐观更新保持 UI 响应。
class AppSettingsController extends Notifier<AppSettings> with SettingsBroadcast, NotificationSettings, HarmonyNameSettings, MirrorPresetSettings {
  static const _languageKey = 'settings.language';
  static const _themeModeKey = 'settings.themeMode';
  static const _scrcpyAlwaysOnTopKey = 'settings.scrcpyAlwaysOnTop';
  static const _mirrorControlsAlwaysVisibleKey =
      'settings.mirrorControlsAlwaysVisible';
  static const _mirrorVideoBitrateKey = 'settings.mirrorVideoBitrate';
  static const _mirrorMaxSizeKey = 'settings.mirrorMaxSize';
  static const _mirrorAudioEnabledKey = 'settings.mirrorAudioEnabled';
  static const _iosMirrorAudioEnabledKey = 'settings.iosMirrorAudioEnabled';
  static const _airplayServerNameKey = 'settings.airplayServerName';
  static const _dlnaServerNameKey = 'settings.dlnaServerName';
  static const _screenshotSavePathKey = 'settings.screenshotSavePath';
  static const _autoIdentifyForegroundAppKey = 'settings.autoIdentifyForegroundApp';
  static const _autoIdentifyIntervalKey = 'settings.autoIdentifyInterval';
  static const _forceHostRecordingKey = 'settings.forceHostRecording';
  static const _autoPowerOffScreenKey = 'settings.autoPowerOffScreen';
  static const _deviceConnectNotificationKey = 'settings.deviceConnectNotification';
  static const _notificationBodyPreviewKey = 'settings.notificationBodyPreview';
  static const _launchAtStartupKey = 'settings.launchAtStartup';
  static const _showWindowShortcutKey = 'settings.showWindowShortcutKey';
  static const _developerModeEnabledKey = 'settings.developerModeEnabled';
  static const _mainSettingsChannel = WindowMethodChannel(
    'any_deck/settings_main',
    mode: ChannelMode.unidirectional,
  );

  @override
  AppSettings build() {
    // 先返回默认设置，SharedPreferences 读取完成后再覆盖真实值。
    _load();
    _setupMethodHandler();
    return const AppSettings();
  }

  void _setupMethodHandler() {
    final currentId = ref.read(windowIdProvider);
    if (currentId.isEmpty) {
      unawaited(_mainSettingsChannel.setMethodCallHandler(_handleSettingsCall));
      return;
    }

    SubWindowMethodDispatcher.registerHandler(_handleSettingsCall);
  }

  Future<dynamic> _handleSettingsCall(MethodCall call) async {
    stdout.writeln('[SettingsController] _handleSettingsCall: method=${call.method}, args=${call.arguments}, currentWindowId=${ref.read(windowIdProvider)}');
    if (call.method == 'change_harmony_share_local_name' && call.arguments is String) {
      await setHarmonyShareLocalName(call.arguments as String);
    } else if (call.method == 'update_harmony_share_local_name' && call.arguments is String) {
      await setHarmonyShareLocalName(call.arguments as String, broadcast: false);
    } else if (call.method == 'update_harmony_share_notifications' && call.arguments is bool) {
      await setHarmonyShareNotifications(call.arguments as bool, broadcast: false);
    } else if (call.method == 'update_harmony_share_directory' && call.arguments is String) {
      await setHarmonyShareReceiveDirectory(call.arguments as String, broadcast: false, validate: false);
    } else if (call.method == 'update_language') {
      final langCode = call.arguments as String;
      await setLanguage(AppLanguage.fromCode(langCode), broadcast: false);
    } else if (call.method == 'update_save_path') {
      final savePath = call.arguments as String;
      await setScreenshotSavePath(savePath, broadcast: false);
    } else if (call.method == 'update_always_on_top') {
      final value = call.arguments as bool;
      await setScrcpyAlwaysOnTop(value, broadcast: false);
    } else if (call.method == 'update_mirror_controls_always_visible') {
      final value = call.arguments as bool;
      await setMirrorControlsAlwaysVisible(value, broadcast: false);
    } else if (call.method == 'update_video_bitrate') {
      final value = call.arguments as int;
      await setMirrorVideoBitrate(value, broadcast: false);
    } else if (call.method == 'update_max_size') {
      final value = call.arguments as int;
      await setMirrorMaxSize(value, broadcast: false);
    } else if (call.method == 'update_audio_enabled') {
      final value = call.arguments as bool;
      await setMirrorAudioEnabled(value, broadcast: false);
    } else if (call.method == 'update_ios_audio_enabled') {
      final value = call.arguments as bool;
      await setIosMirrorAudioEnabled(value, broadcast: false);
    } else if (call.method == 'update_airplay_server_name') {
      await setAirplayServerName(call.arguments as String, broadcast: false);
    } else if (call.method == 'update_dlna_server_name') {
      await setDlnaServerName(call.arguments as String, broadcast: false);
    } else if (call.method == 'update_auto_identify_app') {
      final value = call.arguments as bool;
      await setAutoIdentifyForegroundApp(value, broadcast: false);
    } else if (call.method == 'update_auto_identify_interval') {
      final value = call.arguments as int;
      await setAutoIdentifyInterval(value, broadcast: false);
    } else if (call.method == 'update_force_host_recording') {
      final value = call.arguments as bool;
      await setForceHostRecording(value, broadcast: false);
    } else if (call.method == 'update_auto_power_off_screen') {
      final value = call.arguments as bool;
      await setAutoPowerOffScreen(value, broadcast: false);
    } else if (call.method == 'update_themeMode') {
      final themeName = call.arguments as String;
      final themeMode = _themeModeFromName(themeName);
      await setThemeMode(themeMode, broadcast: false);
    } else if (call.method == 'update_device_connect_notification') {
      final value = call.arguments as bool;
      await setDeviceConnectNotification(value, broadcast: false);
    } else if (call.method == 'update_notification_body_preview') {
      final value = call.arguments as bool;
      await setNotificationBodyPreview(value, broadcast: false);
    } else if (call.method == 'update_launch_at_startup') {
      final value = call.arguments as bool;
      await setLaunchAtStartup(value, broadcast: false);
    } else if (call.method == 'update_developer_mode') {
      final value = call.arguments as bool;
      await setDeveloperModeEnabled(value, broadcast: false);
    }
    return null;
  }

  Future<void> setLanguage(
    AppLanguage language, {
    bool broadcast = true,
  }) async {
    state = state.copyWith(language: language);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_languageKey, language.code);

    if (ref.read(windowIdProvider).isEmpty) {
      unawaited(DesktopWindowTitleService.setMenuLanguage(language.code));
      unawaited(DesktopWindowManagerService.updateTrayMenu(language.code));
    }

    if (broadcast) {
      try {
        await _broadcastSettingChange('update_language', language.code);
      } catch (e) {
        debugPrint('Failed to broadcast language change: $e');
      }
    }
  }

  /// 更新当前主题模式，并持久化到下次启动。
  Future<void> setThemeMode(ThemeMode themeMode, {bool broadcast = true}) async {
    state = state.copyWith(themeMode: themeMode);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themeModeKey, themeMode.name);
    if (broadcast) {
      try {
        await _broadcastSettingChange('update_themeMode', themeMode.name);
      } catch (e) {
        debugPrint('Failed to broadcast theme mode change: $e');
      }
    }
  }

  /// 更新投屏窗口是否保持最前，并持久化。
  Future<void> setScrcpyAlwaysOnTop(bool value, {bool broadcast = true}) async {
    state = state.copyWith(scrcpyAlwaysOnTop: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_scrcpyAlwaysOnTopKey, value);
    if (broadcast) {
      try {
        await _broadcastSettingChange('update_always_on_top', value);
      } catch (e) {
        debugPrint('Failed to broadcast always on top change: $e');
      }
    }
  }

  /// 更新投屏标题栏和工具栏是否始终显示，并持久化。
  Future<void> setMirrorControlsAlwaysVisible(
    bool value, {
    bool broadcast = true,
  }) async {
    state = state.copyWith(mirrorControlsAlwaysVisible: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_mirrorControlsAlwaysVisibleKey, value);
    if (broadcast) {
      try {
        await _broadcastSettingChange(
          'update_mirror_controls_always_visible',
          value,
        );
      } catch (e) {
        debugPrint('Failed to broadcast mirror controls visibility change: $e');
      }
    }
  }

  /// 更新投屏视频比特率，并持久化。
  Future<void> setMirrorVideoBitrate(int value, {bool broadcast = true}) async {
    state = state.copyWith(mirrorVideoBitrate: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_mirrorVideoBitrateKey, value);
    if (broadcast) {
      try {
        await _broadcastSettingChange('update_video_bitrate', value);
      } catch (e) {
        debugPrint('Failed to broadcast video bitrate change: $e');
      }
    }
  }

  /// 更新投屏最佳尺寸，并持久化。
  Future<void> setMirrorMaxSize(int value, {bool broadcast = true}) async {
    state = state.copyWith(mirrorMaxSize: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_mirrorMaxSizeKey, value);
    if (broadcast) {
      try {
        await _broadcastSettingChange('update_max_size', value);
      } catch (e) {
        debugPrint('Failed to broadcast max size change: $e');
      }
    }
  }

  /// 更新投屏音频转发状态，并持久化。
  Future<void> setMirrorAudioEnabled(bool value, {bool broadcast = true}) async {
    state = state.copyWith(mirrorAudioEnabled: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_mirrorAudioEnabledKey, value);
    if (broadcast) {
      try {
        await _broadcastSettingChange('update_audio_enabled', value);
      } catch (e) {
        debugPrint('Failed to broadcast audio enabled change: $e');
      }
    }
  }

  /// 更新 iOS 投屏音频转发状态（同时同步 AirPlay 与 USB 采集音频开关），并持久化。
  Future<void> setIosMirrorAudioEnabled(bool value, {bool broadcast = true}) async {
    state = state.copyWith(iosMirrorAudioEnabled: value);
    AirPlayServerService.instance.setAudioEnabled(value);
    unawaited(IosUsbMirrorService.setGlobalAudioEnabled(value));
    await (await SharedPreferences.getInstance()).setBool(_iosMirrorAudioEnabledKey, value);
    if (broadcast) try { await _broadcastSettingChange('update_ios_audio_enabled', value); } catch (_) {}
  }

  /// 更新 iOS AirPlay 投屏广播名称（默认 AnyDeck-AirPlay），并持久化与跨窗口同步。
  Future<void> setAirplayServerName(String value, {bool broadcast = true}) async {
    final clean = value.trim().isEmpty ? AppSettings.defaultAirplayServerName : value.trim();
    state = state.copyWith(airplayServerName: clean);
    await (await SharedPreferences.getInstance()).setString(_airplayServerNameKey, clean);
    if (broadcast) try { await _broadcastSettingChange('update_airplay_server_name', clean); } catch (_) {}
  }

  /// 更新 DLNA 发现名称，不中断当前视频播放。
  Future<void> setDlnaServerName(String value, {bool broadcast = true}) async {
    final clean = AppSettings.normalizeDlnaServerName(value);
    state = state.copyWith(dlnaServerName: clean);
    await (await SharedPreferences.getInstance()).setString(_dlnaServerNameKey, clean);
    if (ref.read(windowIdProvider).isEmpty) await DlnaRendererService.instance.setServerName(clean);
    if (broadcast) try { await _broadcastSettingChange('update_dlna_server_name', clean); } catch (_) {}
  }

  /// 更新截图/录屏保存路径，并持久化和广播。
  Future<void> setScreenshotSavePath(
    String value, {
    bool broadcast = true,
  }) async {
    state = state.copyWith(screenshotSavePath: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_screenshotSavePathKey, value);

    if (broadcast) {
      try {
        await _broadcastSettingChange('update_save_path', value);
      } catch (e) {
        debugPrint('Failed to broadcast save path change: $e');
      }
    }
  }

  Future<void> setAutoIdentifyForegroundApp(bool value, {bool broadcast = true}) async {
    state = state.copyWith(autoIdentifyForegroundApp: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_autoIdentifyForegroundAppKey, value);
    if (broadcast) {
      try {
        await _broadcastSettingChange('update_auto_identify_app', value);
      } catch (e) {
        debugPrint('Failed to broadcast auto identify app change: $e');
      }
    }
  }

  Future<void> setAutoIdentifyInterval(int value, {bool broadcast = true}) async {
    state = state.copyWith(autoIdentifyInterval: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_autoIdentifyIntervalKey, value);
    if (broadcast) {
      try {
        await _broadcastSettingChange('update_auto_identify_interval', value);
      } catch (e) {
        debugPrint('Failed to broadcast auto identify interval change: $e');
      }
    }
  }

  Future<void> setForceHostRecording(bool value, {bool broadcast = true}) async {
    state = state.copyWith(forceHostRecording: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_forceHostRecordingKey, value);
    if (broadcast) {
      try {
        await _broadcastSettingChange('update_force_host_recording', value);
      } catch (e) {
        debugPrint('Failed to broadcast force host recording change: $e');
      }
    }
  }

  Future<void> setAutoPowerOffScreen(bool value, {bool broadcast = true}) async {
    stdout.writeln('[SettingsController] setAutoPowerOffScreen: value=$value, broadcast=$broadcast, currentWindowId=${ref.read(windowIdProvider)}');
    state = state.copyWith(autoPowerOffScreen: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_autoPowerOffScreenKey, value);
    if (broadcast) {
      try {
        await _broadcastSettingChange('update_auto_power_off_screen', value);
      } catch (e) {
        debugPrint('Failed to broadcast auto power off screen change: $e');
      }
    }
  }

  /// 更新开机自启状态，并持久化和广播。
  Future<void> setLaunchAtStartup(bool value, {bool broadcast = true}) async {
    state = state.copyWith(launchAtStartup: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_launchAtStartupKey, value);

    if (Platform.isMacOS) {
      await DesktopAutoStartService.setEnabled(value);
    }

    if (broadcast) {
      try {
        await _broadcastSettingChange('update_launch_at_startup', value);
      } catch (e) {
        debugPrint('Failed to broadcast launch at startup change: $e');
      }
    }
  }

  /// 更新显示主窗口的快捷键字符（如 '1' 表示 ⌘1），并持久化。
  Future<void> setShowWindowShortcut(String key) async {
    final clean = key.trim().isEmpty ? '1' : key.trim()[0].toLowerCase();
    state = state.copyWith(showWindowShortcutKey: clean);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_showWindowShortcutKey, clean);
  }

  /// 更新开发者模式开关状态，并持久化和跨窗口同步。
  Future<void> setDeveloperModeEnabled(bool value, {bool broadcast = true}) async {
    state = state.copyWith(developerModeEnabled: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_developerModeEnabledKey, value);
    if (broadcast) {
      try {
        await _broadcastSettingChange('update_developer_mode', value);
      } catch (e) {
        debugPrint('Failed to broadcast developer mode change: $e');
      }
    }
  }

  /// 从本地读取设置，缺失字段使用安全默认值。
  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final language = AppLanguage.fromCode(preferences.getString(_languageKey));
    final themeMode = _themeModeFromName(preferences.getString(_themeModeKey));
    final scrcpyAlwaysOnTop =
        preferences.getBool(_scrcpyAlwaysOnTopKey) ?? true;
    final mirrorControlsAlwaysVisible =
        preferences.getBool(_mirrorControlsAlwaysVisibleKey) ?? false;
    final mirrorVideoBitrate =
        preferences.getInt(_mirrorVideoBitrateKey) ?? 8000000;
    final mirrorMaxSize = preferences.getInt(_mirrorMaxSizeKey) ?? 1080;
    final mirrorAudioEnabled =
        preferences.getBool(_mirrorAudioEnabledKey) ?? true;
    final iosMirrorAudioEnabled = preferences.getBool(_iosMirrorAudioEnabledKey) ?? true;
    final rawAirplayName = preferences.getString(_airplayServerNameKey)?.trim() ?? '';
    final airplayServerName = rawAirplayName.isEmpty ? AppSettings.defaultAirplayServerName : rawAirplayName;
    final dlnaServerName = AppSettings.normalizeDlnaServerName(
      preferences.getString(_dlnaServerNameKey),
    );
    AirPlayServerService.instance.setAudioEnabled(iosMirrorAudioEnabled);
    unawaited(IosUsbMirrorService.setGlobalAudioEnabled(iosMirrorAudioEnabled));
    final screenshotSavePath =
        preferences.getString(_screenshotSavePathKey) ?? '';
    final autoIdentifyForegroundApp =
        preferences.getBool(_autoIdentifyForegroundAppKey) ?? false;
    final autoIdentifyInterval =
        preferences.getInt(_autoIdentifyIntervalKey) ?? 3;
    final forceHostRecording =
        preferences.getBool(_forceHostRecordingKey) ?? false;
    final autoPowerOffScreen =
        preferences.getBool(_autoPowerOffScreenKey) ?? false;
    final deviceConnectNotification =
        preferences.getBool(_deviceConnectNotificationKey) ?? true;
    final notificationBodyPreview =
        preferences.getBool(_notificationBodyPreviewKey) ?? true;
    bool launchAtStartup =
        preferences.getBool(_launchAtStartupKey) ?? false;
    if (Platform.isMacOS) {
      try {
        launchAtStartup = await DesktopAutoStartService.isEnabled();
      } catch (_) {}
    }
    final showWindowShortcutKey =
        preferences.getString(_showWindowShortcutKey) ?? '1';
    final developerModeEnabled =
        preferences.getBool(_developerModeEnabledKey) ?? false;
    state = AppSettings(
      language: language,
      themeMode: themeMode,
      scrcpyAlwaysOnTop: scrcpyAlwaysOnTop,
      mirrorControlsAlwaysVisible: mirrorControlsAlwaysVisible,
      mirrorVideoBitrate: mirrorVideoBitrate,
      mirrorMaxSize: mirrorMaxSize,
      mirrorAudioEnabled: mirrorAudioEnabled,
      iosMirrorAudioEnabled: iosMirrorAudioEnabled,
      airplayServerName: airplayServerName,
      dlnaServerName: dlnaServerName,
      screenshotSavePath: screenshotSavePath,
      autoIdentifyForegroundApp: autoIdentifyForegroundApp,
      autoIdentifyInterval: autoIdentifyInterval,
      forceHostRecording: forceHostRecording,
      autoPowerOffScreen: autoPowerOffScreen,
      deviceConnectNotification: deviceConnectNotification,
      notificationBodyPreview: notificationBodyPreview,
      harmonyShareNotifications: preferences.getBool(HarmonySharePreferenceKeys.notifications) ?? true,
      harmonyShareReceiveDirectory: preferences.getString(HarmonySharePreferenceKeys.receiveDirectory) ?? '',
      harmonyShareLocalName: preferences.getString(HarmonySharePreferenceKeys.localName) ?? ShareLocalName.defaultName,
      launchAtStartup: launchAtStartup,
      showWindowShortcutKey: showWindowShortcutKey,
      developerModeEnabled: developerModeEnabled,
    );

    if (ref.read(windowIdProvider).isEmpty) {
      unawaited(DlnaRendererService.instance.setServerName(dlnaServerName));
      unawaited(DesktopWindowTitleService.setMenuLanguage(language.code));
      unawaited(DesktopWindowManagerService.updateTrayMenu(language.code));
    }
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
