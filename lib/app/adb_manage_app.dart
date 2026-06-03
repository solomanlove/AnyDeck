import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'router/app_router.dart';
import 'settings/app_settings_controller.dart';
import 'theme/app_theme.dart';
import 'window/desktop_window_title_service.dart';

/// 应用根组件，统一装配路由、本地化和主题设置。
class AdbManageApp extends ConsumerWidget {

  const AdbManageApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final settings = ref.watch(appSettingsProvider);

    return MaterialApp.router(
      onGenerateTitle: (context) {
        final title = context.l10n.t('appTitle');
        unawaited(DesktopWindowTitleService.setTitle(title));
        return title;
      },
      debugShowCheckedModeBanner: false,
      locale: settings.language.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: settings.themeMode,
      routerConfig: router,
    );
  }
}
