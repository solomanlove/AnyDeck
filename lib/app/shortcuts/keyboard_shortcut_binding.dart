import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一个完整的快捷键：触发键和四种修饰键分别保存，不依赖固定前缀。
/// key 为空表示禁用；左右修饰键等价，普通触发键使用 LogicalKeyboardKey。
@immutable
class KeyboardShortcutBinding {
  const KeyboardShortcutBinding({
    required this.key,
    this.control = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });

  const KeyboardShortcutBinding.disabled()
    : key = null,
      control = false,
      alt = false,
      shift = false,
      meta = false;

  final LogicalKeyboardKey? key;
  final bool control;
  final bool alt;
  final bool shift;
  final bool meta;
  bool get isEnabled => key != null;

  static bool get isMacOS => defaultTargetPlatform == TargetPlatform.macOS;

  /// 旧主窗口按键迁移时保留当前平台的 Command / Ctrl 约定。
  factory KeyboardShortcutBinding.primary(LogicalKeyboardKey key) =>
      KeyboardShortcutBinding(key: key, meta: isMacOS, control: !isMacOS);

  static final _modifiers = <LogicalKeyboardKey>{
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.fn,
    LogicalKeyboardKey.fnLock,
    LogicalKeyboardKey.altGraph,
    LogicalKeyboardKey.hyper,
    LogicalKeyboardKey.superKey,
    LogicalKeyboardKey.shiftLevel5,
  };

  static bool isTrigger(LogicalKeyboardKey key) {
    final id = key.keyId;
    final printable =
        id >= 0x20 && id <= 0x10ffff && !(id >= 0xd800 && id <= 0xdfff);
    return !_modifiers.contains(key) &&
        (printable || LogicalKeyboardKey.findKeyByKeyId(id) != null);
  }

  /// 只由真实 KeyDown 录入；修饰键本身不能作为触发键。
  static KeyboardShortcutBinding? capture(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.synthesized ||
        !isTrigger(event.logicalKey)) {
      return null;
    }
    final keyboard = HardwareKeyboard.instance;
    return KeyboardShortcutBinding(
      key: event.logicalKey,
      control: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
      meta: keyboard.isMetaPressed,
    );
  }

  bool matches(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    return key != null &&
        event.logicalKey == key &&
        keyboard.isControlPressed == control &&
        keyboard.isAltPressed == alt &&
        keyboard.isShiftPressed == shift &&
        keyboard.isMetaPressed == meta;
  }

  Map<String, Object?> toJson() => {
    'keyId': key?.keyId,
    'control': control,
    'alt': alt,
    'shift': shift,
    'meta': meta,
  };

  static KeyboardShortcutBinding? fromJson(Object? value) {
    if (value is! Map ||
        !value.containsKey('keyId') ||
        value['control'] is! bool ||
        value['alt'] is! bool ||
        value['shift'] is! bool ||
        value['meta'] is! bool) {
      return null;
    }
    final id = value['keyId'];
    if (id == null) {
      return value.values.whereType<bool>().any((flag) => flag)
          ? null
          : const KeyboardShortcutBinding.disabled();
    }
    if (id is! int || !isTrigger(LogicalKeyboardKey(id))) return null;
    return KeyboardShortcutBinding(
      key: LogicalKeyboardKey(id),
      control: value['control'] as bool,
      alt: value['alt'] as bool,
      shift: value['shift'] as bool,
      meta: value['meta'] as bool,
    );
  }

  String encode() => jsonEncode(toJson());

  static KeyboardShortcutBinding? decode(String? encoded) {
    if (encoded == null) return null;
    try {
      return fromJson(jsonDecode(encoded));
    } on FormatException {
      return null;
    }
  }

  String label({bool? isMacOS}) {
    if (key == null) return '';
    final mac = isMacOS ?? KeyboardShortcutBinding.isMacOS;
    final modifiers = [
      if (meta && mac) '⌘',
      if (control) mac ? '⌃' : 'Ctrl',
      if (alt) mac ? '⌥' : 'Alt',
      if (shift) mac ? '⇧' : 'Shift',
      if (meta && !mac) 'Meta',
    ];
    final trigger = switch (key) {
      LogicalKeyboardKey.arrowUp => '↑',
      LogicalKeyboardKey.arrowDown => '↓',
      LogicalKeyboardKey.arrowLeft => '←',
      LogicalKeyboardKey.arrowRight => '→',
      LogicalKeyboardKey.space => 'Space',
      _ => key!.keyLabel,
    };
    return [...modifiers, trigger].join(mac ? '' : '+');
  }

  @override
  bool operator ==(Object other) =>
      other is KeyboardShortcutBinding &&
      key == other.key &&
      control == other.control &&
      alt == other.alt &&
      shift == other.shift &&
      meta == other.meta;

  @override
  int get hashCode => Object.hash(key, control, alt, shift, meta);
}
