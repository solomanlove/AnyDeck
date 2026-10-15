import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/features/overview/model/platform_distribution_type.dart';
import 'package:any_deck/features/overview/widget/android_version_distribution_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('HarmonyOS 版本入口展示鸿蒙分布提示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: AndroidVersionInfoIcon(
            currentVersion: 'OpenHarmony-6.1.0.115 (API 23)',
            platform: PlatformDistributionType.harmony,
          ),
        ),
      ),
    );

    expect(
      find.byTooltip('HarmonyOS 版本与 API 版本分布 (点击在新窗口中打开)'),
      findsOneWidget,
    );
  });

  testWidgets('Android 版本入口保持原提示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: AndroidVersionInfoIcon(currentVersion: 'Android 16 (API 36)'),
        ),
      ),
    );

    expect(
      find.byTooltip('Android 平台与 API 版本分布 (点击在新窗口中打开)'),
      findsOneWidget,
    );
  });
}
