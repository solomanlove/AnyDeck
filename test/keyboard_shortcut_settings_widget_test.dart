import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/shortcuts/mirror_shortcut.dart';
import 'package:any_deck/app/shortcuts/window_shortcut.dart';
import 'package:any_deck/features/overview/widget/keyboard_shortcut_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/shortcut_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = ShortcutPlatformMocks();
  setUp(platform.setUp);
  tearDown(platform.tearDown);

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
        // 所有动作的按键按钮应贴齐设置内容的右侧内边距。
        final right =
            tester.getTopRight(find.byType(KeyboardShortcutSettings)).dx - 16;
        for (final action in MirrorShortcut.values) {
          expect(
            tester
                .getTopRight(find.byKey(ValueKey('shortcut-${action.name}')))
                .dx,
            right,
          );
        }
        expect(
          tester
              .getTopRight(find.byKey(const ValueKey('shortcut-main-window')))
              .dx,
          right,
        );
        for (final action in WindowShortcut.values) {
          expect(
            tester
                .getTopRight(
                  find.byKey(ValueKey('shortcut-window-${action.name}')),
                )
                .dx,
            right,
          );
        }
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
          find.textContaining(language == 'zh' ? '已用于' : 'assigned to'),
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
        // 三个通用操作使用同一录入弹窗，覆盖任意修饰键与独立触发键。
        final keys = [
          LogicalKeyboardKey.f10,
          LogicalKeyboardKey.f11,
          LogicalKeyboardKey.f12,
        ];
        for (final action in WindowShortcut.values) {
          final button = find.byKey(ValueKey('shortcut-window-${action.name}'));
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          await tester.tap(button);
          await tester.pumpAndSettle();
          final key = keys[action.index];
          await pressShortcut(
            tester,
            key,
            modifiers: [
              LogicalKeyboardKey.shiftLeft,
              LogicalKeyboardKey.controlLeft,
            ],
          );
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(
            container
                .read(appSettingsProvider)
                .windowShortcuts
                .bindingFor(action),
            KeyboardShortcutBinding(key: key, shift: true, control: true),
          );
        }
        // 关闭键改绑后，原来的 Command+W 可以分配给投屏操作。
        await open();
        await pressShortcut(
          tester,
          LogicalKeyboardKey.keyW,
          modifiers: [LogicalKeyboardKey.metaLeft],
        );
        expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
          container
              .read(appSettingsProvider)
              .mirrorShortcuts
              .bindingFor(MirrorShortcut.screenshot),
          const KeyboardShortcutBinding(
            key: LogicalKeyboardKey.keyW,
            meta: true,
          ),
        );
        // 通用操作与投屏使用同一组合时，同样禁止保存。
        final close = find.byKey(const ValueKey('shortcut-window-closeWindow'));
        await tester.ensureVisible(close);
        await tester.pumpAndSettle();
        await tester.tap(close);
        await tester.pumpAndSettle();
        await pressShortcut(
          tester,
          LogicalKeyboardKey.keyW,
          modifiers: [LogicalKeyboardKey.metaLeft],
        );
        expect(tester.widget<FilledButton>(save).onPressed, null);
        await tester.tap(find.text(language == 'zh' ? '取消' : 'Cancel'));
        await tester.pumpAndSettle();
        final persisted = WindowShortcutSettings.decode(
          prefs.getString(WindowShortcutSettings.preferenceKey),
        );
        expect(
          persisted.bindingFor(WindowShortcut.quitApp).key,
          LogicalKeyboardKey.f12,
        );
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox.shrink());
      }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));
    }
  }
}
