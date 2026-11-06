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
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windows, null);
  });

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('快捷键设置 $language $brightness 可修改、冲突拦截、禁用和恢复', (tester) async {
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
        await tester.ensureVisible(selector);
        await tester.pumpAndSettle();
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('⌘⌥Z'),
          240,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('⌘⌥Z'));
        await tester.pumpAndSettle();
        expect(
          container
              .read(appSettingsProvider)
              .mirrorShortcuts
              .keyFor(MirrorShortcut.screenshot),
          'z',
        );

        // 冲突回调通过真实设置行进入，不能覆盖返回键已有的绑定。
        tester.widget<DropdownButton<String>>(selector).onChanged!('b');
        await tester.pumpAndSettle();
        expect(
          container
              .read(appSettingsProvider)
              .mirrorShortcuts
              .keyFor(MirrorShortcut.screenshot),
          'z',
        );
        expect(
          find.textContaining(language == 'zh' ? '已用于' : 'assigned to'),
          findsOneWidget,
        );
        tester.widget<DropdownButton<String>>(selector).onChanged!('');
        await tester.pumpAndSettle();
        expect(
          container
              .read(appSettingsProvider)
              .mirrorShortcuts
              .keyFor(MirrorShortcut.screenshot),
          '',
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
        tester.widget<DropdownButton<String>>(main).onChanged!('5');
        await tester.pumpAndSettle();
        expect(container.read(appSettingsProvider).showWindowShortcutKey, '5');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('settings.showWindowShortcutKey'), '5');
        expect(tester.takeException(), null);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));
    }
  }
}
