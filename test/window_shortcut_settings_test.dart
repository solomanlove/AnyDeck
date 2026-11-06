import 'dart:convert';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/shortcuts/mirror_shortcut.dart';
import 'package:any_deck/app/shortcuts/window_shortcut.dart';
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

  test('通用操作默认值无冲突，完整修饰键和禁用可序列化', () {
    const custom = KeyboardShortcutBinding(
      key: LogicalKeyboardKey.f9,
      control: true,
      alt: true,
      shift: true,
      meta: true,
    );
    final changed = const WindowShortcutSettings()
        .withBinding(WindowShortcut.closeWindow, custom)
        .withBinding(
          WindowShortcut.quitApp,
          const KeyboardShortcutBinding.disabled(),
        );
    final restored = WindowShortcutSettings.decode(changed.encode());
    expect(restored.bindingFor(WindowShortcut.closeWindow), custom);
    expect(restored.bindingFor(WindowShortcut.quitApp).isEnabled, false);
    expect({
      for (final action in WindowShortcut.values) action.defaultBinding,
    }, hasLength(3));
    final app = const AppSettings().copyWith(windowShortcuts: changed);
    expect(
      app.copyWith(autoPowerOffScreen: true).windowShortcuts,
      same(changed),
    );
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = AppLocalizations(locale);
      for (final action in WindowShortcut.values) {
        expect(l10n.t(action.labelKey), isNot(action.labelKey));
      }
      final prompt = l10n
          .t('pressShortcutAgainToQuit')
          .replaceAll('{shortcut}', custom.label());
      expect(prompt, contains(custom.label()));
      expect(prompt, isNot(contains('{shortcut}')));
    }
  });

  test('通用操作完全相同才冲突，旧默认键释放后可重新分配', () {
    final close = WindowShortcut.closeWindow.defaultBinding;
    expect(
      () => const WindowShortcutSettings().withBinding(
        WindowShortcut.openSettings,
        close,
      ),
      throwsA(isA<ShortcutConflictException>()),
    );
    final changed = const WindowShortcutSettings()
        .withBinding(
          WindowShortcut.closeWindow,
          const KeyboardShortcutBinding(key: LogicalKeyboardKey.f6),
        )
        .withBinding(WindowShortcut.openSettings, close);
    expect(changed.bindingFor(WindowShortcut.openSettings), close);
    expect(
      changed.bindingFor(WindowShortcut.closeWindow).key,
      LogicalKeyboardKey.f6,
    );
  });

  test('通用操作与主窗口、投屏交叉检测冲突，无静态保留键', () {
    final previousClose = WindowShortcut.closeWindow.defaultBinding;
    final mirrors = const MirrorShortcutSettings().withBinding(
      MirrorShortcut.screenshot,
      previousClose,
    );
    final app = const AppSettings().copyWith(mirrorShortcuts: mirrors);
    expect(
      app.shortcutConflict(
        previousClose,
        mirrorAction: MirrorShortcut.screenshot,
      ),
      WindowShortcut.closeWindow.labelKey,
    );
    final moved = app.copyWith(
      windowShortcuts: const WindowShortcutSettings().withBinding(
        WindowShortcut.closeWindow,
        const KeyboardShortcutBinding(key: LogicalKeyboardKey.f6),
      ),
    );
    expect(
      moved.shortcutConflict(
        previousClose,
        mirrorAction: MirrorShortcut.screenshot,
      ),
      null,
    );
    expect(
      moved.shortcutConflict(
        previousClose,
        windowAction: WindowShortcut.closeWindow,
      ),
      MirrorShortcut.screenshot.labelKey,
    );
    expect(
      moved.shortcutConflict(
        moved.mainWindowBinding,
        windowAction: WindowShortcut.closeWindow,
      ),
      'mainWindowShortcut',
    );
    expect(
      moved.shortcutConflict(
        const KeyboardShortcutBinding.disabled(),
        windowAction: WindowShortcut.closeWindow,
      ),
      null,
    );
  });

  test('损坏及重复的通用配置回退默认值', () {
    final duplicate = {
      'closeWindow': WindowShortcut.openSettings.defaultBinding.toJson(),
    };
    for (final encoded in [
      'null',
      '[1]',
      '{',
      '{"closeWindow":42}',
      jsonEncode(duplicate),
    ]) {
      expect(WindowShortcutSettings.decode(encoded).overrides, isEmpty);
    }
  });

  for (final id in ['', 'child']) {
    test('通用组合键保存、主子窗口同步、清除与恢复 $id', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(ShortcutTestSettings.new),
          windowIdProvider.overrideWithValue(id),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appSettingsProvider.notifier);
      const quit = KeyboardShortcutBinding(
        key: LogicalKeyboardKey.f8,
        control: true,
        shift: true,
      );
      final changed = const WindowShortcutSettings().withBinding(
        WindowShortcut.quitApp,
        quit,
      );
      await controller.setWindowShortcuts(changed);
      final prefs = await SharedPreferences.getInstance();
      expect(
        WindowShortcutSettings.decode(
          prefs.getString(WindowShortcutSettings.preferenceKey),
        ).bindingFor(WindowShortcut.quitApp),
        quit,
      );
      expect(
        container
            .read(appSettingsProvider)
            .windowShortcuts
            .bindingFor(WindowShortcut.quitApp),
        quit,
      );
      expect(
        platform.channelCalls.where(
          (call) => call['method'] == WindowShortcutSettings.channelMethod,
        ),
        hasLength(id.isEmpty ? 1 : 2),
      );
      if (id.isEmpty) {
        expect(
          platform.trayCalls.last.arguments.toString(),
          contains(quit.label()),
        );
      }
      platform.channelCalls.clear();
      await controller.setWindowShortcuts(changed, broadcast: false);
      expect(platform.channelCalls, isEmpty);
      var cleared = changed;
      for (final action in WindowShortcut.values) {
        cleared = cleared.withBinding(
          action,
          const KeyboardShortcutBinding.disabled(),
        );
      }
      await controller.setWindowShortcuts(cleared);
      for (final action in WindowShortcut.values) {
        expect(
          container
              .read(appSettingsProvider)
              .windowShortcuts
              .bindingFor(action)
              .isEnabled,
          false,
        );
      }
      await controller.setWindowShortcuts(const WindowShortcutSettings());
      expect(prefs.getString(WindowShortcutSettings.preferenceKey), '{}');
    });
  }

  test('保存交叉冲突时不修改当前状态和持久化数据', () async {
    final container = ProviderContainer(
      overrides: [appSettingsProvider.overrideWith(ShortcutTestSettings.new)],
    );
    addTearDown(container.dispose);
    final controller = container.read(appSettingsProvider.notifier);
    final before = container.read(appSettingsProvider);
    final invalid = before.windowShortcuts.withBinding(
      WindowShortcut.closeWindow,
      before.mirrorShortcuts.bindingFor(MirrorShortcut.screenshot),
    );
    await expectLater(
      controller.setWindowShortcuts(invalid),
      throwsA(isA<ShortcutConflictException>()),
    );
    expect(container.read(appSettingsProvider), same(before));
    expect(
      (await SharedPreferences.getInstance()).getString(
        WindowShortcutSettings.preferenceKey,
      ),
      null,
    );
    final close = before.windowShortcuts.bindingFor(WindowShortcut.closeWindow);
    await expectLater(
      controller.setMirrorShortcuts(
        before.mirrorShortcuts.withBinding(MirrorShortcut.screenshot, close),
      ),
      throwsA(isA<ShortcutConflictException>()),
    );
    await expectLater(
      controller.setMainWindowShortcut(close),
      throwsA(isA<ShortcutConflictException>()),
    );
    expect(container.read(appSettingsProvider), same(before));
  });
}
