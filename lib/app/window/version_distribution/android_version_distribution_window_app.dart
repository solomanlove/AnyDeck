import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../l10n/app_localizations.dart';
import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../window_close_shortcut.dart';
import '../desktop_window_title_service.dart';
import '../../../features/overview/model/platform_distribution_type.dart';
import '../../../features/overview/widget/platform_version_distribution_shell_view.dart';

/// 平台版本分布独立 macOS 窗口入口，支持 Android、HarmonyOS、iOS 三端切换。
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
    final platformStr = argument['platform'] as String?;
    final initialPlatform = platformStr == 'harmony'
        ? PlatformDistributionType.harmony
        : platformStr == 'ios'
            ? PlatformDistributionType.ios
            : PlatformDistributionType.android;

    return MaterialApp(
      onGenerateTitle: (context) {
        final title = context.l10n.t('androidApiDistribution');
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
      home: WindowCloseShortcut(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: PlatformVersionDistributionShellView(
            isStandaloneWindow: true,
            initialPlatform: initialPlatform,
            initialVersion: initialVersion,
          ),
        ),
      ),
    );
  }
}
