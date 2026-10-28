import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_name_editor.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_panels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('名称编辑字节计数、同步与禁用 ${brightness.name} $language', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(480, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final saves = <String>[];
        Widget host({String value = '测试 Mac', bool disabled = false}) =>
            MaterialApp(
              theme: buildAppTheme(brightness),
              locale: Locale(language),
              supportedLocales: const [Locale('zh'), Locale('en')],
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                ...GlobalMaterialLocalizations.delegates,
              ],
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      HarmonyShareIdentity(
                        enabled: false,
                        localName: value,
                        onChanged: (_) {},
                      ),
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: HarmonyShareNameEditor(
                          value: value,
                          disabled: disabled,
                          onSave: saves.add,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
        final l10n = AppLocalizations(Locale(language));
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();
        expect(find.text('测试 Mac'), findsNWidgets(2));
        await tester.enterText(find.byType(TextField), '中' * 8);
        await tester.pump();
        expect(find.text('24/24 bytes'), findsOneWidget);
        await tester.tap(find.text(l10n.t('harmonyShareSaveName')));
        expect(saves, ['中' * 8]);
        await tester.enterText(find.byType(TextField), '中' * 9);
        await tester.pump();
        expect(
          find.text(l10n.t('harmonyShareLocalNameInvalid')),
          findsOneWidget,
        );
        final save = tester.widget<TextButton>(
          find.ancestor(
            of: find.text(l10n.t('harmonyShareSaveName')),
            matching: find.byType(TextButton),
          ),
        );
        expect(save.onPressed, isNull);
        await tester.tap(find.text(l10n.t('harmonyShareResetName')));
        expect(saves.last, 'AnyDeck');
        await tester.pumpWidget(host(value: '同步 Mac', disabled: true));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '同步 Mac',
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
