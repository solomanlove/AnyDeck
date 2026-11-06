import 'dart:convert';

import 'package:flutter/services.dart';

import 'keyboard_shortcut_binding.dart';

export 'keyboard_shortcut_binding.dart';

/// 投屏操作与默认按键的唯一目录；设置页和工具栏共用。
enum MirrorShortcut {
  power('power', 'p'),
  screenPower('screenPowerToggle', 'o'),
  volumeUp('volumeUp', 'up'),
  volumeDown('volumeDown', 'down'),
  back('back', 'b'),
  home('home', 'h'),
  recentApps('menuKey', 'm'),
  inputClipboard('getClipboardInput', 'v'),
  clipboard('clipboardTitle', 'c'),
  focus('focus', 'f'),
  screenshot('shortcutScreenshot', 's'),
  saveScreenshot('shortcutSaveScreenshot', 'd'),
  whiteboard('shortcutWhiteboard', 'w'),
  recording('shortcutRecording', 'r'),
  mouseRecording('shortcutMouseRecording', 't'),
  deviceSettings('deviceSettings', 'e'),
  fullScreen('shortcutFullScreen', 'enter'),
  alwaysOnTop('shortcutAlwaysOnTop', 'a'),
  mirrorSettings('mirrorQualitySettings', 'q'),
  reconnect('reconnectRetry', 'x');

  const MirrorShortcut(this.labelKey, this.defaultKey);

  final String labelKey;
  final String defaultKey;
}

/// 投屏快捷键的完整组合配置；只保存覆盖项，旧版单按键配置自动迁移。
class MirrorShortcutSettings {
  const MirrorShortcutSettings([this.overrides = const {}]);

  static const preferenceKey = 'settings.mirrorShortcuts';
  static const channelMethod = 'update_mirror_shortcuts';
  final Map<String, KeyboardShortcutBinding> overrides;

  /// 旧配置使用的按键目录，仅用于默认值和历史字符串迁移。
  static final keys = <String, LogicalKeyboardKey>{
    for (var code = 97; code <= 122; code++)
      String.fromCharCode(code): LogicalKeyboardKey(code),
    for (var code = 48; code <= 57; code++)
      String.fromCharCode(code): LogicalKeyboardKey(code),
    'up': LogicalKeyboardKey.arrowUp,
    'down': LogicalKeyboardKey.arrowDown,
    'left': LogicalKeyboardKey.arrowLeft,
    'right': LogicalKeyboardKey.arrowRight,
    'enter': LogicalKeyboardKey.enter,
  };

  static KeyboardShortcutBinding legacyBinding(String key, {bool? isMacOS}) {
    if (key.isEmpty) return const KeyboardShortcutBinding.disabled();
    final mac = isMacOS ?? KeyboardShortcutBinding.isMacOS;
    return KeyboardShortcutBinding(
      key: keys[key]!,
      meta: mac,
      control: !mac,
      alt: true,
    );
  }

  KeyboardShortcutBinding bindingFor(MirrorShortcut action, {bool? isMacOS}) =>
      overrides[action.name] ??
      legacyBinding(action.defaultKey, isMacOS: isMacOS);

  /// 兼容已有按键调用；新录入使用 withBinding 保存完整修饰键。
  String keyFor(MirrorShortcut action) {
    final key = bindingFor(action).key;
    if (key == null) return '';
    return keys.entries.where((entry) => entry.value == key).firstOrNull?.key ??
        key.keyLabel;
  }

  MirrorShortcut? conflict(
    MirrorShortcut action,
    KeyboardShortcutBinding binding,
  ) {
    if (!binding.isEnabled) return null;
    for (final other in MirrorShortcut.values) {
      if (other != action && bindingFor(other) == binding) return other;
    }
    return null;
  }

  MirrorShortcutSettings withBinding(
    MirrorShortcut action,
    KeyboardShortcutBinding binding,
  ) {
    if ((binding.key != null &&
            !KeyboardShortcutBinding.isTrigger(binding.key!)) ||
        binding.reservedLabelKey != null ||
        conflict(action, binding) != null) {
      throw ArgumentError.value(binding, 'binding');
    }
    final updated = {...overrides}..remove(action.name);
    if (binding != legacyBinding(action.defaultKey)) {
      updated[action.name] = binding;
    }
    return MirrorShortcutSettings(Map.unmodifiable(updated));
  }

  MirrorShortcutSettings withKey(MirrorShortcut action, String key) {
    if (key.isNotEmpty && !keys.containsKey(key)) {
      throw ArgumentError.value(key, 'key');
    }
    return withBinding(action, legacyBinding(key));
  }

  /// v2 保存 keyId 和四个修饰键；同时兼容 v1 的 action -> 字符串结构。
  static MirrorShortcutSettings decode(String? encoded) {
    if (encoded == null) return const MirrorShortcutSettings();
    try {
      final data = jsonDecode(encoded);
      if (data is! Map<String, dynamic>) return const MirrorShortcutSettings();
      final modern = data.containsKey('version');
      if (modern && data['version'] != 2) return const MirrorShortcutSettings();
      final values = modern ? data['bindings'] : data;
      if (values is! Map) return const MirrorShortcutSettings();
      final overrides = <String, KeyboardShortcutBinding>{};
      for (final action in MirrorShortcut.values) {
        if (!values.containsKey(action.name)) continue;
        final value = values[action.name];
        final binding = modern
            ? KeyboardShortcutBinding.fromJson(value)
            : value is String && (value.isEmpty || keys.containsKey(value))
            ? legacyBinding(value)
            : null;
        if (binding == null || binding.reservedLabelKey != null) {
          return const MirrorShortcutSettings();
        }
        overrides[action.name] = binding;
      }
      final settings = MirrorShortcutSettings(Map.unmodifiable(overrides));
      final used = <KeyboardShortcutBinding>{};
      for (final action in MirrorShortcut.values) {
        final binding = settings.bindingFor(action);
        if (binding.isEnabled && !used.add(binding)) {
          return const MirrorShortcutSettings();
        }
      }
      return settings;
    } on FormatException {
      return const MirrorShortcutSettings();
    }
  }

  String encode() => jsonEncode({
    'version': 2,
    'bindings': overrides.map(
      (action, binding) => MapEntry(action, binding.toJson()),
    ),
  });

  MirrorShortcut? match(KeyEvent event, {bool? isMacOS}) {
    for (final action in MirrorShortcut.values) {
      if (bindingFor(action, isMacOS: isMacOS).matches(event)) return action;
    }
    return null;
  }

  String label(MirrorShortcut action, {required bool isMacOS}) =>
      bindingFor(action, isMacOS: isMacOS).label(isMacOS: isMacOS);
}
