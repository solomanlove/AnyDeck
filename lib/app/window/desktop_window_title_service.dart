import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// 同步 Flutter 本地化标题到桌面系统原生窗口标题栏。
class DesktopWindowTitleService {
  DesktopWindowTitleService._();

  static const _channel = MethodChannel('any_deck/window');

  /// 同步当前 macOS 子窗口的原生标题栏主题，System 交还系统管理。
  static Future<void> setAppearance(ThemeMode mode) async {
    if (defaultTargetPlatform != TargetPlatform.macOS || kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('setWindowAppearance', mode.name);
    } on MissingPluginException {
      // 测试环境没有原生 Runner。
    } on PlatformException catch (error) {
      if (error.code != 'no_window') rethrow;
      // 子窗口首帧前尚未关联 NSWindow，首帧回调会按最新设置重试。
    }
  }

  /// 设置当前桌面窗口标题；移动端或未注册原生通道时静默跳过。
  static Future<void> setTitle(String title) async {
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.fuchsia) {
      return;
    }

    try {
      // 主 Runner 同时更新 GTK HeaderBar；子引擎缺少私有通道时再回退。
      await _channel.invokeMethod<void>('setWindowTitle', title);
    } on MissingPluginException {
      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux) {
        try {
          await windowManager.setTitle(title);
        } on MissingPluginException {
          // 测试环境没有原生插件，忽略即可。
        }
      }
    }
  }

  /// 设置原生菜单语言；移动端或未注册原生通道时静默跳过。
  static Future<void> setMenuLanguage(String languageCode) async {
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.fuchsia) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('setMenuLanguage', languageCode);
    } on MissingPluginException {
      // 非桌面目标或测试环境没有原生 Runner，忽略即可。
    }
  }
}
