import 'dart:convert';

import 'package:flutter/services.dart';

import 'keyboard_shortcut_binding.dart';

/// 主窗口和所有独立窗口共用的应用操作，默认值遵循当前平台约定。
enum WindowShortcut {
  closeWindow('shortcutCloseWindow', LogicalKeyboardKey.keyW),
  openSettings('shortcutOpenSettings', LogicalKeyboardKey.comma),
  quitApp('shortcutQuit', LogicalKeyboardKey.keyQ);

  const WindowShortcut(this.labelKey, this.defaultKey);
  final String labelKey;
  final LogicalKeyboardKey defaultKey;
  KeyboardShortcutBinding get defaultBinding =>
      KeyboardShortcutBinding.primary(defaultKey);
}

/// 冲突携带操作文案 key，由设置 UI 使用当前语言展示。
class ShortcutConflictException implements Exception {
  const ShortcutConflictException(this.labelKey);
  final String labelKey;
}

/// 应用级操作的完整组合键覆盖项，空覆盖使用默认值，disabled 显式禁用。
class WindowShortcutSettings {
  const WindowShortcutSettings([this.overrides = const {}]);
  static const preferenceKey = 'settings.windowShortcuts';
  static const channelMethod = 'update_window_shortcuts';
  final Map<WindowShortcut, KeyboardShortcutBinding> overrides;

  KeyboardShortcutBinding bindingFor(WindowShortcut action) =>
      overrides[action] ?? action.defaultBinding;

  WindowShortcutSettings withBinding(
    WindowShortcut action,
    KeyboardShortcutBinding binding,
  ) {
    if (binding.key != null &&
        !KeyboardShortcutBinding.isTrigger(binding.key!)) {
      throw ArgumentError.value(binding, 'binding');
    }
    for (final other in WindowShortcut.values) {
      if (other != action &&
          binding.isEnabled &&
          bindingFor(other) == binding) {
        throw ShortcutConflictException(other.labelKey);
      }
    }
    final updated = {...overrides}..remove(action);
    if (binding != action.defaultBinding) updated[action] = binding;
    return WindowShortcutSettings(Map.unmodifiable(updated));
  }

  WindowShortcut? match(KeyEvent event) {
    for (final action in WindowShortcut.values) {
      if (bindingFor(action).matches(event)) return action;
    }
    return null;
  }

  String encode() => jsonEncode(
    overrides.map((action, binding) => MapEntry(action.name, binding.toJson())),
  );

  static WindowShortcutSettings decode(String? encoded) {
    if (encoded == null) return const WindowShortcutSettings();
    try {
      final data = jsonDecode(encoded);
      if (data is! Map) return const WindowShortcutSettings();
      final values = <WindowShortcut, KeyboardShortcutBinding>{};
      for (final action in WindowShortcut.values) {
        if (!data.containsKey(action.name)) continue;
        final binding = KeyboardShortcutBinding.fromJson(data[action.name]);
        if (binding == null) return const WindowShortcutSettings();
        values[action] = binding;
      }
      final settings = WindowShortcutSettings(Map.unmodifiable(values));
      final used = <KeyboardShortcutBinding>{};
      for (final action in WindowShortcut.values) {
        final binding = settings.bindingFor(action);
        if (binding.isEnabled && !used.add(binding)) {
          return const WindowShortcutSettings();
        }
      }
      return settings;
    } on FormatException {
      return const WindowShortcutSettings();
    }
  }
}
