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
      expect(
        MirrorShortcutSettings.decode(invalid).encode(),
        const MirrorShortcutSettings().encode(),
      );
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
        jsonDecode(changed.encode()),
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
      expect(
        prefs.getString(MirrorShortcutSettings.preferenceKey),
        const MirrorShortcutSettings().encode(),
      );
    });

    test('完整主窗口快捷键保存、广播和禁用 $windowId', () async {
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(ShortcutTestSettings.new),
          windowIdProvider.overrideWithValue(windowId),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appSettingsProvider.notifier);
      const binding = KeyboardShortcutBinding(
        key: LogicalKeyboardKey.f8,
        shift: true,
        control: true,
      );
      await controller.setMainWindowShortcut(binding);
      final prefs = await SharedPreferences.getInstance();
      expect(
        decodeMainWindowShortcut(
          prefs.getString(mainWindowShortcutPreferenceKey),
        ),
        binding,
      );
      expect(container.read(appSettingsProvider).mainWindowBinding, binding);
      expect(
        calls.where(
          (call) => call['method'] == mainWindowShortcutChannelMethod,
        ),
        hasLength(windowId.isEmpty ? 1 : 2),
      );
      calls.clear();
      await controller.setMainWindowShortcut(
        const KeyboardShortcutBinding.disabled(),
        broadcast: false,
      );
      expect(
        container.read(appSettingsProvider).mainWindowBinding.isEnabled,
        false,
      );
      expect(
        decodeMainWindowShortcut(
          prefs.getString(mainWindowShortcutPreferenceKey),
        )?.isEnabled,
        false,
      );
      expect(calls, isEmpty);
    });
  }

  test('v2 保留完整修饰键，同键不同修饰键允许共存，完全相同才冲突', () {
    const ctrlS = KeyboardShortcutBinding(
      key: LogicalKeyboardKey.keyS,
      control: true,
    );
    const shiftS = KeyboardShortcutBinding(
      key: LogicalKeyboardKey.keyS,
      shift: true,
    );
    const all = KeyboardShortcutBinding(
      key: LogicalKeyboardKey.f12,
      control: true,
      alt: true,
      shift: true,
      meta: true,
    );
    final settings = const MirrorShortcutSettings()
        .withBinding(MirrorShortcut.screenshot, ctrlS)
        .withBinding(MirrorShortcut.saveScreenshot, shiftS)
        .withBinding(MirrorShortcut.recording, all);
    final decoded = MirrorShortcutSettings.decode(settings.encode());
    expect(decoded.bindingFor(MirrorShortcut.screenshot), ctrlS);
    expect(decoded.bindingFor(MirrorShortcut.saveScreenshot), shiftS);
    expect(decoded.bindingFor(MirrorShortcut.recording), all);
    expect(
      decoded.conflict(MirrorShortcut.home, ctrlS),
      MirrorShortcut.screenshot,
    );
    expect(
      () => decoded.withBinding(MirrorShortcut.home, ctrlS),
      throwsArgumentError,
    );
    expect(jsonDecode(settings.encode())['version'], 2);
    expect(KeyboardShortcutBinding.decode(all.encode()), all);
  });

  test('旧按键配置迁移保留键值和禁用状态，再保存使用新格式', () {
    final migrated = MirrorShortcutSettings.decode(
      '{"screenshot":"z","power":""}',
    );
    expect(
      migrated.bindingFor(MirrorShortcut.screenshot),
      MirrorShortcutSettings.legacyBinding('z'),
    );
    expect(migrated.bindingFor(MirrorShortcut.power).isEnabled, false);
    expect(
      MirrorShortcutSettings.decode(
        migrated.encode(),
      ).bindingFor(MirrorShortcut.screenshot),
      migrated.bindingFor(MirrorShortcut.screenshot),
    );
  });

  test('窗口冲突按当前配置判断，损坏完整组合键和仅修饰键不能写入', () {
    final occupied = WindowShortcut.closeWindow.defaultBinding;
    expect(
      const AppSettings().shortcutConflict(
        occupied,
        mirrorAction: MirrorShortcut.screenshot,
      ),
      WindowShortcut.closeWindow.labelKey,
    );
    expect(decodeMainWindowShortcut(occupied.encode()), occupied);
    expect(KeyboardShortcutBinding.fromJson({'keyId': 123}), null);
    final modifier = const KeyboardShortcutBinding(
      key: LogicalKeyboardKey.controlLeft,
    ).toJson();
    expect(KeyboardShortcutBinding.fromJson(modifier), null);
    for (final data in [
      {'version': 3, 'bindings': {}},
      {'version': 2, 'bindings': []},
      {
        'version': 2,
        'bindings': {'screenshot': modifier},
      },
    ]) {
      expect(
        MirrorShortcutSettings.decode(jsonEncode(data)).overrides,
        isEmpty,
      );
    }
  });
}
