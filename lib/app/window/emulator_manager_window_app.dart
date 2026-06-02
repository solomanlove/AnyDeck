import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../l10n/app_localizations.dart';
import '../settings/app_settings_controller.dart';
import '../theme/app_theme.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';

/// 模拟器管理独立窗口的应用入口。
class EmulatorManagerWindowApp extends ConsumerWidget {
  const EmulatorManagerWindowApp({
    super.key,
    required this.windowId,
    required this.argument,
  });

  final int windowId;
  final Map<String, dynamic> argument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.t('emulators'),
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
      home: const Scaffold(
        body: EmulatorListPanel(isStandalone: true),
      ),
    );
  }
}
