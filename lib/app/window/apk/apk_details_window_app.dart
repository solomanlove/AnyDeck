import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/apk/apk_details_page.dart';
import '../../l10n/app_localizations.dart';
import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../desktop_window_title_service.dart';
import '../window_close_shortcut.dart';

/// APK 子引擎入口；主题语言使用已有设置广播，原生标题随语言更新。
class ApkDetailsWindowApp extends ConsumerWidget {
  const ApkDetailsWindowApp({super.key, required this.argument});
  final Map<String, dynamic> argument;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final path = argument['path'] as String;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) {
        final title =
            '${context.l10n.t('apkTitle')} · ${Uri.file(path).pathSegments.last}';
        unawaited(DesktopWindowTitleService.setTitle(title));
        return title;
      },
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
      home: WindowCloseShortcut(
        child: ApkDetailsPage(
          path: path,
          mainWindowId: argument['mainWindowId'] as String,
        ),
      ),
    );
  }
}
