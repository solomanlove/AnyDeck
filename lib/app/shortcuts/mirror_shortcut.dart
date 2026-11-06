import 'dart:convert';

import 'package:flutter/services.dart';

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

/// 使用固定的 Command+Option / Ctrl+Alt 前缀，避免抢占普通输入和系统编辑键。
/// 空按键表示禁用；只保存与默认值不同的覆盖项。
class MirrorShortcutSettings {
  const MirrorShortcutSettings([this.overrides = const {}]);

  static const preferenceKey = 'settings.mirrorShortcuts';
  static const channelMethod = 'update_mirror_shortcuts';
  final Map<String, String> overrides;

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

  String keyFor(MirrorShortcut action) =>
      overrides[action.name] ?? action.defaultKey;

  MirrorShortcut? conflict(MirrorShortcut action, String key) {
    if (key.isEmpty) return null;
    for (final other in MirrorShortcut.values) {
      if (other != action && keyFor(other) == key) return other;
    }
    return null;
  }

  MirrorShortcutSettings withKey(MirrorShortcut action, String key) {
    if ((key.isNotEmpty && !keys.containsKey(key)) ||
        conflict(action, key) != null) {
      throw ArgumentError.value(key, 'key');
    }
    final updated = {...overrides}..remove(action.name);
    if (key != action.defaultKey) updated[action.name] = key;
    return MirrorShortcutSettings(Map.unmodifiable(updated));
  }

  /// 对持久化和跨窗口输入执行整表校验，异常配置整体回退默认值。
  static MirrorShortcutSettings decode(String? encoded) {
    if (encoded == null) return const MirrorShortcutSettings();
    try {
      final data = jsonDecode(encoded);
      if (data is! Map<String, dynamic>) {
        return const MirrorShortcutSettings();
      }
      final overrides = <String, String>{};
      for (final action in MirrorShortcut.values) {
        final value = data[action.name];
        if (value == null) continue;
        if (value is! String ||
            (value.isNotEmpty && !keys.containsKey(value))) {
          return const MirrorShortcutSettings();
        }
        overrides[action.name] = value;
      }
      final settings = MirrorShortcutSettings(Map.unmodifiable(overrides));
      final used = <String>{};
      for (final action in MirrorShortcut.values) {
        final key = settings.keyFor(action);
        if (key.isNotEmpty && !used.add(key)) {
          return const MirrorShortcutSettings();
        }
      }
      return settings;
    } on FormatException {
      return const MirrorShortcutSettings();
    }
  }

  String encode() => jsonEncode(overrides);

  MirrorShortcut? match(KeyEvent event, {required bool isMacOS}) {
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isAltPressed ||
        keyboard.isShiftPressed ||
        (isMacOS
            ? !keyboard.isMetaPressed || keyboard.isControlPressed
            : !keyboard.isControlPressed || keyboard.isMetaPressed)) {
      return null;
    }
    for (final action in MirrorShortcut.values) {
      if (keys[keyFor(action)] == event.logicalKey) return action;
    }
    return null;
  }

  static String keyLabel(String key) => switch (key) {
    'up' => '↑',
    'down' => '↓',
    'left' => '←',
    'right' => '→',
    'enter' => 'Enter',
    _ => key.toUpperCase(),
  };

  String label(MirrorShortcut action, {required bool isMacOS}) {
    final key = keyFor(action);
    if (key.isEmpty) return '';
    return '${isMacOS ? '⌘⌥' : 'Ctrl+Alt+'}${keyLabel(key)}';
  }
}
