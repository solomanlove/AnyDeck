import 'dart:convert';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/shortcuts/mirror_shortcut.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/shortcut_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const windows = MethodChannel('mixin.one/desktop_multi_window');
  const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
  final calls = <Map<dynamic, dynamic>>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    messenger.setMockMethodCallHandler(
      windows,
      (call) async => call.method == 'getAllWindows'
          ? [
              {'windowId': 'other', 'windowArgument': '{"kind":"mirror"}'},
            ]
          : null,
    );
    messenger.setMockMethodCallHandler(channels, (call) async {
      if (call.method == 'invokeMethod') calls.add(call.arguments as Map);
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(windows, null);
    messenger.setMockMethodCallHandler(channels, null);
  });

  test('默认投屏按键有效且无冲突，中英文目录全部有文案', () {
    const settings = MirrorShortcutSettings();
    final used = <String>{};
    for (final action in MirrorShortcut.values) {
      expect(
        MirrorShortcutSettings.keys.containsKey(settings.keyFor(action)),
        true,
      );
      expect(used.add(settings.keyFor(action)), true);
      for (final locale in AppLocalizations.supportedLocales) {
        expect(
          AppLocalizations(locale).t(action.labelKey),
          isNot(action.labelKey),
        );
      }
    }
    expect(settings.label(MirrorShortcut.screenshot, isMacOS: true), '⌘⌥S');
    expect(
      settings.label(MirrorShortcut.screenshot, isMacOS: false),
      'Ctrl+Alt+S',
    );
  });

  test('修改、禁用及重启解码保留配置，拒绝占用按键', () {
    const defaults = MirrorShortcutSettings();
    expect(
      () => defaults.withKey(MirrorShortcut.screenshot, 'b'),
      throwsArgumentError,
    );
    expect(
      () => defaults.withKey(MirrorShortcut.screenshot, 'bad'),
      throwsArgumentError,
    );
    final changed = defaults
        .withKey(MirrorShortcut.screenshot, 'z')
        .withKey(MirrorShortcut.power, '');
    final restored = MirrorShortcutSettings.decode(changed.encode());
    expect(restored.keyFor(MirrorShortcut.screenshot), 'z');
    expect(restored.label(MirrorShortcut.power, isMacOS: true), '');
    expect(defaults.keyFor(MirrorShortcut.screenshot), 's');
    final app = const AppSettings().copyWith(mirrorShortcuts: restored);
    expect(
      app.copyWith(autoPowerOffScreen: true).mirrorShortcuts,
      same(restored),
    );
  });

  test('主窗口旧的无效快捷键回退默认，已有有效按键保留', () {
    expect(normalizeMainWindowShortcut('unsupported'), '1');
    expect(normalizeMainWindowShortcut(null), '1');
    expect(normalizeMainWindowShortcut(' M '), 'm');
  });

  test('损坏存储及跨窗口错误类型安全回退，允许一次交换两个按键', () {
    for (final invalid in [
      '[1]',
      'null',
      '{',
      '{"power":42}',
      '{"power":"s"}',
      '{"power":"invalid"}',
    ]) {
      expect(MirrorShortcutSettings.decode(invalid).encode(), '{}');
    }
    final swapped = MirrorShortcutSettings.decode(
      '{"power":"s","screenshot":"p"}',
    );
    expect(swapped.keyFor(MirrorShortcut.power), 's');
    expect(swapped.keyFor(MirrorShortcut.screenshot), 'p');
  });

  for (final windowId in ['', 'child']) {
    test('快捷键持久化并广播到窗口 $windowId；接收时不重复广播', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(ShortcutTestSettings.new),
          windowIdProvider.overrideWithValue(windowId),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appSettingsProvider.notifier);
      final changed = const MirrorShortcutSettings().withKey(
        MirrorShortcut.screenshot,
        'z',
      );
      await controller.setMirrorShortcuts(changed);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString(MirrorShortcutSettings.preferenceKey)!),
        {'screenshot': 'z'},
      );
      final updates = calls
          .where(
            (call) => call['method'] == MirrorShortcutSettings.channelMethod,
          )
          .toList();
      expect(updates, hasLength(windowId.isEmpty ? 1 : 2));
      expect(
        updates.every((call) => call['arguments'] == changed.encode()),
        true,
      );
      calls.clear();
      await controller.setMirrorShortcuts(
        MirrorShortcutSettings.decode(changed.encode()),
        broadcast: false,
      );
      expect(calls, isEmpty);
      expect(
        container
            .read(appSettingsProvider)
            .mirrorShortcuts
            .keyFor(MirrorShortcut.screenshot),
        'z',
      );
      await controller.setMirrorShortcuts(const MirrorShortcutSettings());
      expect(prefs.getString(MirrorShortcutSettings.preferenceKey), '{}');
    });
  }
}
