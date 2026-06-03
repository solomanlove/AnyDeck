import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

/// 全局唯一的窗口 ID Provider，默认为 0（主窗口）。
final windowIdProvider = Provider<int>((ref) => 0);

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

  @override
  AppSettings build() {
    // 先返回默认设置，SharedPreferences 读取完成后再覆盖真实值。
    _load();
    _setupMethodHandler();
    return const AppSettings();
  }

  void _setupMethodHandler() {
    DesktopMultiWindow.setMethodHandler((MethodCall call, int fromWindowId) async {
      if (call.method == 'update_language') {
        final langCode = call.arguments as String;
        await setLanguage(AppLanguage.fromCode(langCode), broadcast: false);
      }
      return null;
    });
  }

  /// 更新当前语言，并持久化到下次启动。
  Future<void> setLanguage(AppLanguage language, {bool broadcast = true}) async {
    state = state.copyWith(language: language);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_languageKey, language.code);

    if (broadcast) {
      try {
        final currentId = ref.read(windowIdProvider);

        if (currentId == 0) {
          // 主窗口：广播给所有子窗口
          final subWindowIds = await DesktopMultiWindow.getAllSubWindowIds();
          for (final windowId in subWindowIds) {
            await DesktopMultiWindow.invokeMethod(
              windowId,
              'update_language',
              language.code,
            );
          }
        } else {
          // 子窗口：发送到主窗口
          await DesktopMultiWindow.invokeMethod(
            0,
            'update_language',
            language.code,
          );
        }
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

  /// 从本地读取设置，缺失字段使用安全默认值。
  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final language = AppLanguage.fromCode(preferences.getString(_languageKey));
    final themeMode = _themeModeFromName(preferences.getString(_themeModeKey));
    final scrcpyAlwaysOnTop =
        preferences.getBool(_scrcpyAlwaysOnTopKey) ?? true;
    state = AppSettings(
      language: language,
      themeMode: themeMode,
      scrcpyAlwaysOnTop: scrcpyAlwaysOnTop,
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
}
