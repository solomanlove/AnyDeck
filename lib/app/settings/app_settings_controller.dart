import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

/// 全局唯一的窗口 ID Provider，主窗口默认为空字符串。
final windowIdProvider = Provider<String>((ref) => '');

/// 通过 SharedPreferences 持久化的应用设置 Riverpod 状态。
final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

/// 负责加载和保存设置，并通过乐观更新保持 UI 响应。
class AppSettingsController extends Notifier<AppSettings> {
  static const _languageKey = 'settings.language';
  static const _themeModeKey = 'settings.themeMode';
  static const _scrcpyAlwaysOnTopKey = 'settings.scrcpyAlwaysOnTop';
  static const _mirrorVideoBitrateKey = 'settings.mirrorVideoBitrate';
  static const _mirrorMaxSizeKey = 'settings.mirrorMaxSize';
  static const _mirrorAudioEnabledKey = 'settings.mirrorAudioEnabled';
  static const _screenshotSavePathKey = 'settings.screenshotSavePath';
  static const _mainSettingsChannel = WindowMethodChannel(
    'adb_manage/settings_main',
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

    unawaited(
      WindowController.fromCurrentEngine()
          .then((controller) {
            return controller.setWindowMethodHandler(_handleSettingsCall);
          })
          .catchError((e) {
            debugPrint('Failed to register multi-window settings handler: $e');
          }),
    );
  }

  Future<dynamic> _handleSettingsCall(MethodCall call) async {
    if (call.method == 'update_language') {
      final langCode = call.arguments as String;
      await setLanguage(AppLanguage.fromCode(langCode), broadcast: false);
    } else if (call.method == 'update_save_path') {
      final savePath = call.arguments as String;
      await setScreenshotSavePath(savePath, broadcast: false);
    }
    return null;
  }

  /// 更新当前语言，并持久化到下次启动。
  Future<void> setLanguage(
    AppLanguage language, {
    bool broadcast = true,
  }) async {
    state = state.copyWith(language: language);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_languageKey, language.code);

    if (broadcast) {
      try {
        await _broadcastSettingChange('update_language', language.code);
      } catch (e) {
        debugPrint('Failed to broadcast language change: $e');
      }
    }
  }

  /// 更新当前主题模式，并持久化到下次启动。
  Future<void> setThemeMode(ThemeMode themeMode) async {
    state = state.copyWith(themeMode: themeMode);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themeModeKey, themeMode.name);
  }

  /// 更新投屏窗口是否保持最前，并持久化。
  Future<void> setScrcpyAlwaysOnTop(bool value) async {
    state = state.copyWith(scrcpyAlwaysOnTop: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_scrcpyAlwaysOnTopKey, value);
  }

  /// 更新投屏视频比特率，并持久化。
  Future<void> setMirrorVideoBitrate(int value) async {
    state = state.copyWith(mirrorVideoBitrate: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_mirrorVideoBitrateKey, value);
  }

  /// 更新投屏最佳尺寸，并持久化。
  Future<void> setMirrorMaxSize(int value) async {
    state = state.copyWith(mirrorMaxSize: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_mirrorMaxSizeKey, value);
  }

  /// 更新投屏音频转发状态，并持久化。
  Future<void> setMirrorAudioEnabled(bool value) async {
    state = state.copyWith(mirrorAudioEnabled: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_mirrorAudioEnabledKey, value);
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

  /// 从本地读取设置，缺失字段使用安全默认值。
  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final language = AppLanguage.fromCode(preferences.getString(_languageKey));
    final themeMode = _themeModeFromName(preferences.getString(_themeModeKey));
    final scrcpyAlwaysOnTop =
        preferences.getBool(_scrcpyAlwaysOnTopKey) ?? true;
    final mirrorVideoBitrate =
        preferences.getInt(_mirrorVideoBitrateKey) ?? 8000000;
    final mirrorMaxSize = preferences.getInt(_mirrorMaxSizeKey) ?? 1080;
    final mirrorAudioEnabled =
        preferences.getBool(_mirrorAudioEnabledKey) ?? true;
    final screenshotSavePath =
        preferences.getString(_screenshotSavePathKey) ?? '';
    state = AppSettings(
      language: language,
      themeMode: themeMode,
      scrcpyAlwaysOnTop: scrcpyAlwaysOnTop,
      mirrorVideoBitrate: mirrorVideoBitrate,
      mirrorMaxSize: mirrorMaxSize,
      mirrorAudioEnabled: mirrorAudioEnabled,
      screenshotSavePath: screenshotSavePath,
    );
  }

  /// 将本地存储的枚举名称映射回 Flutter 的 ThemeMode。
  ThemeMode _themeModeFromName(String? name) {
    return switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> _broadcastSettingChange(String method, Object value) async {
    final currentId = ref.read(windowIdProvider);
    if (currentId.isNotEmpty) {
      await _mainSettingsChannel.invokeMethod(method, value);
    }

    final windows = await WindowController.getAll();
    for (final window in windows) {
      if (window.windowId == currentId || window.arguments.isEmpty) {
        continue;
      }
      await window.invokeMethod(method, value);
    }
  }
}
