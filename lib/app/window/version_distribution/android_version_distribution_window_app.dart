import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../l10n/app_localizations.dart';
import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../window_close_shortcut.dart';
import '../../../features/overview/widget/android_api_distribution_view.dart';

/// Android 平台与 API 版本分布独立 macOS 窗口入口。
class AndroidVersionDistributionWindowApp extends ConsumerWidget {
  const AndroidVersionDistributionWindowApp({
    super.key,
    required this.windowId,
    required this.argument,
  });

  final String windowId;
  final Map<String, dynamic> argument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final initialVersion = argument['initialVersion'] as String?;

    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.t('androidApiDistribution'),
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
      home: WindowCloseShortcut(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: AndroidApiDistributionView(
            isStandaloneWindow: true,
            initialVersion: initialVersion,
          ),
        ),
      ),
    );
  }
}
