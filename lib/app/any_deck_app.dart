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
class AnyDeckApp extends ConsumerWidget {

  const AnyDeckApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);// 路由配置
    final settings = ref.watch(appSettingsProvider);// 应用设置

    return MaterialApp.router(
      onGenerateTitle: (context) {
        final title = context.l10n.t('appTitle');// 应用标题
        unawaited(DesktopWindowTitleService.setTitle(title));// 设置原生桌面的窗口标题
        return title;
      },
      debugShowCheckedModeBanner: false,// 关闭调试模式banner
      locale: settings.language.locale,// 应用语言
      supportedLocales: AppLocalizations.supportedLocales,// 支持的语言
      // 本地化委托
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: buildAppTheme(Brightness.light),// 光明主题
      darkTheme: buildAppTheme(Brightness.dark),// 暗黑主题
      themeMode: settings.themeMode,// 主题模式
      routerConfig: router,
    );
  }
}
