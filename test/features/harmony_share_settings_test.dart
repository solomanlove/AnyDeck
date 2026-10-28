import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child, Brightness brightness, String language) =>
      MaterialApp(
        theme: buildAppTheme(brightness),
        locale: Locale(language),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(body: AlertDialog(scrollable: true, content: child)),
      );
  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('设置窄窗口与禁用态 ${brightness.name} $language', (tester) async {
        tester.view.physicalSize = const Size(480, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var chosen = 0;
        var permission = 0;
        Widget panel({bool busy = false, bool saving = false}) =>
            HarmonyShareSettingsPanel(
              notifications: true,
              directory: '/synthetic/folder-with-a-long-name/接收文件目录',
              permission: 'denied',
              saving: saving,
              busy: busy,
              deliveryFailed: true,
              errorKey: 'harmonyShareDirectoryError',
              onNotifications: (_) {},
              onChooseDirectory: () => chosen++,
              onResetDirectory: () => chosen++,
              onPermission: () => permission++,
              onRefreshPermission: () => permission++,
            );
        await tester.pumpWidget(host(panel(), brightness, language));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final l10n = AppLocalizations(Locale(language));
        await tester.ensureVisible(
          find.text(l10n.t('harmonyShareChooseDirectory')),
        );
        await tester.tap(find.text(l10n.t('harmonyShareChooseDirectory')));
        expect(chosen, 1);
        await tester.pumpWidget(host(panel(busy: true), brightness, language));
        await tester.pumpAndSettle();
        final choose = tester.widget<TextButton>(
          find.ancestor(
            of: find.text(l10n.t('harmonyShareChooseDirectory')),
            matching: find.byType(TextButton),
          ),
        );
        expect(choose.onPressed, isNull);
        await tester.pumpWidget(
          host(panel(saving: true), brightness, language),
        );
        await tester.pump();
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
          isNull,
        );
        expect(permission, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
