import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_name_editor.dart';
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
        Widget panel({bool busy = false, bool saving = false, String state = 'denied'}) =>
            HarmonyShareSettingsPanel(
              nameEditor: HarmonyShareNameEditor(
                value: 'Macos-AnyDeck',
                disabled: busy || saving,
                onSave: (_) {},
              ),
              notifications: true,
              directory: '/synthetic/folder-with-a-long-name/接收文件目录',
              permission: state,
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
        expect(find.text(l10n.t('harmonyShareDirectMode')), findsNothing);
        expect(find.text(l10n.t('harmonyShareDirectModeHint')), findsNothing);
        expect(find.byType(SwitchListTile), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
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
          tester.widgetList<SwitchListTile>(find.byType(SwitchListTile))
              .every((tile) => tile.onChanged == null),
          isTrue,
        );
        expect(permission, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(host(panel(state: 'unknown'), brightness, language));
        await tester.pumpAndSettle();
        expect(find.text(l10n.t('harmonySharePermissionUnknown')), findsOneWidget);
        expect(find.text(l10n.t('harmonySharePermissionNeeded')), findsNothing);
        expect(find.text(l10n.t('harmonyShareNotificationFailed')), findsOneWidget);
        expect(find.text(l10n.t('openSystemSettings')), findsOneWidget);
        expect(find.text(l10n.t('requestPermission')), findsNothing);
        expect(permission, 0);
        final refresh = find.byTooltip(l10n.t('harmonySharePermissionRefresh'));
        await tester.ensureVisible(refresh);
        await tester.tap(refresh);
        expect(permission, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
