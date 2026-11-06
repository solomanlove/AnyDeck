import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 隔离原生初始化，保留真实的设置更新、持久化和广播方法。
class ShortcutTestSettings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings();
}

/// 为快捷键测试提供真实本地化和主题，container 可在窗口之间隔离。
Widget shortcutTestApp({
  required ProviderContainer container,
  required Widget child,
  String language = 'zh',
  Brightness brightness = Brightness.light,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    locale: Locale(language),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    theme: ThemeData(brightness: brightness),
    home: Scaffold(body: child),
  ),
);
