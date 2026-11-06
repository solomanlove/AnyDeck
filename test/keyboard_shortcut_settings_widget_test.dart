import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/shortcuts/mirror_shortcut.dart';
import 'package:any_deck/features/overview/widget/keyboard_shortcut_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/shortcut_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windows = MethodChannel('mixin.one/desktop_multi_window');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windows, (_) async => []);
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windows, null),
  );

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('直接录入 $language $brightness 支持任意修饰键、冲突、取消、清除与重置', (
        tester,
      ) async {
        final container = ProviderContainer(
          overrides: [
            appSettingsProvider.overrideWith(ShortcutTestSettings.new),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          shortcutTestApp(
            container: container,
            language: language,
            brightness: brightness,
            child: const SingleChildScrollView(
              child: SizedBox(width: 520, child: KeyboardShortcutSettings()),
            ),
          ),
        );
        final selector = find.byKey(const ValueKey('shortcut-screenshot'));
        Future<void> open() async {
          await tester.ensureVisible(selector);
          await tester.pumpAndSettle();
          await tester.tap(selector);
          await tester.pumpAndSettle();
        }

        final save = find.byKey(const ValueKey('shortcut-record-save'));
        await open();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(tester.widget<FilledButton>(save).onPressed, null);
        const custom = KeyboardShortcutBinding(
          key: LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        );
        await pressShortcut(
          tester,
          LogicalKeyboardKey.keyS,
          modifiers: [
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.shiftLeft,
          ],
        );
        expect(find.text('⌃⇧S'), findsOneWidget);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
          container
              .read(appSettingsProvider)
              .mirrorShortcuts
              .bindingFor(MirrorShortcut.screenshot),
          custom,
        );

        await open();
        await pressShortcut(
          tester,
          LogicalKeyboardKey.keyB,
          modifiers: [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.altLeft],
        );
        expect(
          find.textContaining(language == 'zh' ? '已用于' : 'assigned to'),
          findsOneWidget,
        );
        expect(tester.widget<FilledButton>(save).onPressed, null);
        await pressShortcut(
          tester,
          LogicalKeyboardKey.keyB,
          modifiers: [LogicalKeyboardKey.shiftLeft],
        );
        expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
        await tester.tap(find.text(language == 'zh' ? '取消' : 'Cancel'));
        await tester.pumpAndSettle();
        expect(
          container
              .read(appSettingsProvider)
              .mirrorShortcuts
              .bindingFor(MirrorShortcut.screenshot),
          custom,
        );

        await open();
        await pressShortcut(
          tester,
          LogicalKeyboardKey.keyW,
          modifiers: [LogicalKeyboardKey.metaLeft],
        );
        expect(
          find.textContaining(
            language == 'zh' ? '请选择其他组合键' : 'Choose another shortcut',
          ),
          findsOneWidget,
        );
        expect(tester.widget<FilledButton>(save).onPressed, null);
        await pressShortcut(tester, LogicalKeyboardKey.f6);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
          container
              .read(appSettingsProvider)
              .mirrorShortcuts
              .bindingFor(MirrorShortcut.screenshot),
          const KeyboardShortcutBinding(key: LogicalKeyboardKey.f6),
        );
        await open();
        await tester.tap(find.byKey(const ValueKey('shortcut-record-clear')));
        await tester.pumpAndSettle();
        expect(
          container
              .read(appSettingsProvider)
              .mirrorShortcuts
              .bindingFor(MirrorShortcut.screenshot)
              .isEnabled,
          false,
        );
        final reset = find.byKey(const ValueKey('shortcut-reset'));
        await tester.ensureVisible(reset);
        await tester.pumpAndSettle();
        await tester.tap(reset);
        await tester.pumpAndSettle();
        expect(
          container
              .read(appSettingsProvider)
              .mirrorShortcuts
              .keyFor(MirrorShortcut.screenshot),
          's',
        );

        final main = find.byKey(const ValueKey('shortcut-main-window'));
        await tester.ensureVisible(main);
        await tester.pumpAndSettle();
        await tester.tap(main);
        await tester.pumpAndSettle();
        await pressShortcut(
          tester,
          LogicalKeyboardKey.f8,
          modifiers: [
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.altLeft,
            LogicalKeyboardKey.shiftLeft,
            LogicalKeyboardKey.metaLeft,
          ],
        );
        await tester.tap(save);
        await tester.pumpAndSettle();
        const mainBinding = KeyboardShortcutBinding(
          key: LogicalKeyboardKey.f8,
          control: true,
          alt: true,
          shift: true,
          meta: true,
        );
        expect(
          container.read(appSettingsProvider).mainWindowBinding,
          mainBinding,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(
          KeyboardShortcutBinding.decode(
            prefs.getString(mainWindowShortcutPreferenceKey),
          ),
          mainBinding,
        );
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox.shrink());
      }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));
    }
  }
}
