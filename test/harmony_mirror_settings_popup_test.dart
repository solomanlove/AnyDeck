import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/control/device_settings_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('HarmonyOS 投屏设置弹窗展示三个系统跳转入口', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          locale: Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: const Scaffold(
            body: DeviceSettingsPopup(
              deviceId: 'harmony-device',
              isHarmony: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('系统页面跳转'), findsOneWidget);
    expect(find.text('系统设置'), findsOneWidget);
    expect(find.text('Wi-Fi 设置'), findsOneWidget);
    expect(find.text('应用管理'), findsOneWidget);
    expect(find.text('显示布局边界'), findsNothing);
  });
}
