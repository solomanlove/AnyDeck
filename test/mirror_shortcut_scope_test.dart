import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/shortcuts/mirror_shortcut_scope.dart';
import 'package:any_deck/app/window/mirror/mirror_toolbar_button.dart';
import 'package:any_deck/app/window/window_close_shortcut.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shortcut_test_fixture.dart';

/// 重现设备输入层会消费按键的场景，确认本地操作先于设备键盘映射。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platformMocks = ShortcutPlatformMocks();
  setUp(platformMocks.setUp);
  tearDown(platformMocks.tearDown);

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('$platform 本地快捷键只触发一次，repeat/up 不转发，普通输入与粘贴保留', (tester) async {
      final container = ProviderContainer(
        overrides: [appSettingsProvider.overrideWith(ShortcutTestSettings.new)],
      );
      addTearDown(container.dispose);
      final forwarded = <LogicalKeyboardKey>[];
      var screenshots = 0;
      var saved = 0;
      await tester.pumpWidget(
        shortcutTestApp(
          container: container,
          child: WindowCloseShortcut(
            autofocus: false,
            child: MirrorShortcutScope(
              child: Column(
                children: [
                  Focus(
                    autofocus: true,
                    onKeyEvent: (_, event) {
                      forwarded.add(event.logicalKey);
                      return KeyEventResult.handled;
                    },
                    child: const Text('device'),
                  ),
                  MirrorToolbarButton(
                    icon: const Icon(Icons.camera),
                    tooltip: 'capture',
                    shortcut: MirrorShortcut.screenshot,
                    longPressShortcut: MirrorShortcut.saveScreenshot,
                    onPressed: () => screenshots++,
                    onLongPress: () => saved++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      Focus.of(tester.element(find.text('device'))).requestFocus();
      await tester.pump();
      final modifier = platform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(modifier);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      expect(screenshots, 1);
      expect(forwarded, isNot(contains(LogicalKeyboardKey.keyS)));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(modifier);
      expect(
        forwarded,
        containsAll([LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyV]),
      );
      await _chord(tester, modifier, LogicalKeyboardKey.keyD);
      expect(saved, 1);
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(modifier);
      expect(
        platformMocks.windowCalls.where((method) => method == 'close'),
        hasLength(1),
      );
      expect(forwarded, isNot(contains(LogicalKeyboardKey.keyW)));
      await container
          .read(appSettingsProvider.notifier)
          .setMirrorShortcuts(
            const MirrorShortcutSettings().withKey(
              MirrorShortcut.screenshot,
              'z',
            ),
            broadcast: false,
          );
      await tester.pump();
      await _chord(tester, modifier, LogicalKeyboardKey.keyS);
      expect(screenshots, 1);
      await _chord(tester, modifier, LogicalKeyboardKey.keyZ);
      expect(screenshots, 2);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip).first).message,
        contains(platform == TargetPlatform.macOS ? '⌘⌥Z' : 'Ctrl+Alt+Z'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant({platform}));
  }

  testWidgets('禁用按钮、隐藏平台操作、弹窗和卸载均不会执行，自动隐藏仍可使用', (tester) async {
    final container = ProviderContainer(
      overrides: [appSettingsProvider.overrideWith(ShortcutTestSettings.new)],
    );
    addTearDown(container.dispose);
    var calls = 0;
    var busy = false;
    var visible = true;
    late StateSetter update;
    late BuildContext page;
    await tester.pumpWidget(
      shortcutTestApp(
        container: container,
        child: MirrorShortcutScope(
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              page = context;
              return Column(
                children: [
                  if (visible)
                    Opacity(
                      opacity: 0,
                      child: MirrorToolbarButton(
                        icon: const Icon(Icons.camera),
                        tooltip: 'capture',
                        shortcut: MirrorShortcut.screenshot,
                        isLoading: busy,
                        onPressed: () => calls++,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await _chord(tester, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyS);
    expect(calls, 1);
    update(() => busy = true);
    await tester.pump();
    await _chord(tester, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyS);
    expect(calls, 1);
    update(() => busy = false);
    await tester.pump();
    showDialog<void>(
      context: page,
      builder: (_) => const AlertDialog(content: TextField(autofocus: true)),
    );
    await tester.pumpAndSettle();
    await _chord(tester, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyS);
    expect(calls, 1);
    Navigator.of(page).pop();
    await tester.pumpAndSettle();
    update(() => visible = false);
    await tester.pump();
    await _chord(tester, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyS);
    await _chord(tester, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyP);
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await _chord(tester, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyS);
    expect(calls, 1);
    expect(tester.takeException(), null);
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('$platform 自定义完整修饰键和普通单键精确匹配', (tester) async {
      final container = ProviderContainer(
        overrides: [appSettingsProvider.overrideWith(ShortcutTestSettings.new)],
      );
      addTearDown(container.dispose);
      var calls = 0;
      final forwarded = <LogicalKeyboardKey>[];
      await tester.pumpWidget(
        shortcutTestApp(
          container: container,
          child: MirrorShortcutScope(
            child: Column(
              children: [
                Focus(
                  onKeyEvent: (_, event) {
                    forwarded.add(event.logicalKey);
                    return KeyEventResult.handled;
                  },
                  child: const Text('device'),
                ),
                MirrorToolbarButton(
                  icon: const Icon(Icons.camera),
                  tooltip: 'capture',
                  shortcut: MirrorShortcut.screenshot,
                  onPressed: () => calls++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      Focus.of(tester.element(find.text('device'))).requestFocus();
      await tester.pump();
      const bindings = [
        KeyboardShortcutBinding(key: LogicalKeyboardKey.f6),
        KeyboardShortcutBinding(key: LogicalKeyboardKey.keyK, control: true),
        KeyboardShortcutBinding(key: LogicalKeyboardKey.keyS, shift: true),
        KeyboardShortcutBinding(
          key: LogicalKeyboardKey.keyZ,
          meta: true,
          shift: true,
        ),
        KeyboardShortcutBinding(
          key: LogicalKeyboardKey.f9,
          control: true,
          alt: true,
          shift: true,
          meta: true,
        ),
      ];
      for (final binding in bindings) {
        await container
            .read(appSettingsProvider.notifier)
            .setMirrorShortcuts(
              const MirrorShortcutSettings().withBinding(
                MirrorShortcut.screenshot,
                binding,
              ),
              broadcast: false,
            );
        await tester.pump();
        forwarded.clear();
        final before = calls;
        final modifiers = [
          if (binding.control) LogicalKeyboardKey.controlRight,
          if (binding.alt) LogicalKeyboardKey.altRight,
          if (binding.shift) LogicalKeyboardKey.shiftRight,
          if (binding.meta) LogicalKeyboardKey.metaRight,
        ];
        await pressShortcut(tester, binding.key!, modifiers: modifiers);
        expect(calls, before + 1);
        expect(forwarded, isNot(contains(binding.key)));
        expect(
          tester.widget<Tooltip>(find.byType(Tooltip).first).message,
          contains(binding.label()),
        );
        if (!binding.alt) {
          await pressShortcut(
            tester,
            binding.key!,
            modifiers: [...modifiers, LogicalKeyboardKey.altLeft],
          );
          expect(calls, before + 1);
          expect(forwarded, contains(binding.key));
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant({platform}));
  }
}

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyUpEvent(modifier);
}
