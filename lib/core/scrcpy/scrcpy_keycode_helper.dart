import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// A helper class to map Flutter [LogicalKeyboardKey] keys to Android keycodes,
/// and handle binary serialization of keycode and text control messages for the scrcpy protocol.
class ScrcpyKeycodeHelper {
  // Mapping of Flutter's LogicalKeyboardKey to Android KeyEvent keycodes
  static final Map<LogicalKeyboardKey, int> _keyMap = {
    // Letters
    LogicalKeyboardKey.keyA: 29,
    LogicalKeyboardKey.keyB: 30,
    LogicalKeyboardKey.keyC: 31,
    LogicalKeyboardKey.keyD: 32,
    LogicalKeyboardKey.keyE: 33,
    LogicalKeyboardKey.keyF: 34,
    LogicalKeyboardKey.keyG: 35,
    LogicalKeyboardKey.keyH: 36,
    LogicalKeyboardKey.keyI: 37,
    LogicalKeyboardKey.keyJ: 38,
    LogicalKeyboardKey.keyK: 39,
    LogicalKeyboardKey.keyL: 40,
    LogicalKeyboardKey.keyM: 41,
    LogicalKeyboardKey.keyN: 42,
    LogicalKeyboardKey.keyO: 43,
    LogicalKeyboardKey.keyP: 44,
    LogicalKeyboardKey.keyQ: 45,
    LogicalKeyboardKey.keyR: 46,
    LogicalKeyboardKey.keyS: 47,
    LogicalKeyboardKey.keyT: 48,
    LogicalKeyboardKey.keyU: 49,
    LogicalKeyboardKey.keyV: 50,
    LogicalKeyboardKey.keyW: 51,
    LogicalKeyboardKey.keyX: 52,
    LogicalKeyboardKey.keyY: 53,
    LogicalKeyboardKey.keyZ: 54,

    // Digits
    LogicalKeyboardKey.digit0: 7,
    LogicalKeyboardKey.digit1: 8,
    LogicalKeyboardKey.digit2: 9,
    LogicalKeyboardKey.digit3: 10,
    LogicalKeyboardKey.digit4: 11,
    LogicalKeyboardKey.digit5: 12,
    LogicalKeyboardKey.digit6: 13,
    LogicalKeyboardKey.digit7: 14,
    LogicalKeyboardKey.digit8: 15,
    LogicalKeyboardKey.digit9: 16,

    // Numpad Digits
    LogicalKeyboardKey.numpad0: 7,
    LogicalKeyboardKey.numpad1: 8,
    LogicalKeyboardKey.numpad2: 9,
    LogicalKeyboardKey.numpad3: 10,
    LogicalKeyboardKey.numpad4: 11,
    LogicalKeyboardKey.numpad5: 12,
    LogicalKeyboardKey.numpad6: 13,
    LogicalKeyboardKey.numpad7: 14,
    LogicalKeyboardKey.numpad8: 15,
    LogicalKeyboardKey.numpad9: 16,

    // Controls
    LogicalKeyboardKey.enter: 66,
    LogicalKeyboardKey.numpadEnter: 66,
    LogicalKeyboardKey.escape: 111,
    LogicalKeyboardKey.backspace: 67,
    LogicalKeyboardKey.tab: 61,
    LogicalKeyboardKey.space: 62,

    // Arrows
    LogicalKeyboardKey.arrowLeft: 21,
    LogicalKeyboardKey.arrowRight: 22,
    LogicalKeyboardKey.arrowUp: 19,
    LogicalKeyboardKey.arrowDown: 20,

    // Navigation
    LogicalKeyboardKey.home: 122,
    LogicalKeyboardKey.end: 123,
    LogicalKeyboardKey.pageUp: 92,
    LogicalKeyboardKey.pageDown: 93,
    LogicalKeyboardKey.delete: 112,

    // Modifiers
    LogicalKeyboardKey.shiftLeft: 59,
    LogicalKeyboardKey.shiftRight: 60,
    LogicalKeyboardKey.controlLeft: 113,
    LogicalKeyboardKey.controlRight: 114,
    LogicalKeyboardKey.altLeft: 57,
    LogicalKeyboardKey.altRight: 58,
    LogicalKeyboardKey.metaLeft: 117,
    LogicalKeyboardKey.metaRight: 118,

    // Functions
    LogicalKeyboardKey.f1: 131,
    LogicalKeyboardKey.f2: 132,
    LogicalKeyboardKey.f3: 133,
    LogicalKeyboardKey.f4: 134,
    LogicalKeyboardKey.f5: 135,
    LogicalKeyboardKey.f6: 136,
    LogicalKeyboardKey.f7: 137,
    LogicalKeyboardKey.f8: 138,
    LogicalKeyboardKey.f9: 139,
    LogicalKeyboardKey.f10: 140,
    LogicalKeyboardKey.f11: 141,
    LogicalKeyboardKey.f12: 142,

    // Common Symbols
    LogicalKeyboardKey.comma: 55,
    LogicalKeyboardKey.period: 56,
    LogicalKeyboardKey.backquote: 68,
    LogicalKeyboardKey.minus: 69,
    LogicalKeyboardKey.equal: 70,
    LogicalKeyboardKey.bracketLeft: 71,
    LogicalKeyboardKey.bracketRight: 72,
    LogicalKeyboardKey.backslash: 73,
    LogicalKeyboardKey.semicolon: 74,
    LogicalKeyboardKey.quote: 75,
    LogicalKeyboardKey.slash: 76,
  };

  /// Returns the Android keycode for a given Flutter LogicalKeyboardKey, or null if not mapped.
  static int? getAndroidKeycode(LogicalKeyboardKey key) {
    return _keyMap[key];
  }

  /// Check if the key is a modifier or control key that should be sent as keycode even when text input is active.
  static bool isControlKey(LogicalKeyboardKey key) {
    final controlKeys = {
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.backspace,
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.delete,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
    };
    return controlKeys.contains(key);
  }

  /// Helper to get Android meta state from Flutter KeyEvent.
  static int getAndroidMetaState(KeyEvent event) {
    int metaState = 0;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed) {
      metaState |= 0x01; // AMETA_SHIFT_ON
    }
    if (keyboard.isAltPressed) {
      metaState |= 0x02; // AMETA_ALT_ON
    }
    if (keyboard.isControlPressed) {
      metaState |= 0x1000; // AMETA_CTRL_ON
    }
    if (keyboard.isMetaPressed) {
      metaState |= 0x10000; // AMETA_META_ON
    }
    return metaState;
  }

  /// Serialize keycode event to bytes (14 bytes total)
  /// Format:
  /// - 1 byte: type = 0
  /// - 1 byte: action (0 = down, 1 = up, 2 = repeat)
  /// - 4 bytes: keycode (uint32)
  /// - 4 bytes: repeat (uint32)
  /// - 4 bytes: metaState (uint32)
  static Uint8List serializeKeyCodeEvent({
    required int action,
    required int keycode,
    required int repeat,
    required int metaState,
  }) {
    final buffer = ByteData(14);
    buffer.setUint8(0, 0); // type = 0 (inject keycode)
    buffer.setUint8(1, action);
    buffer.setUint32(2, keycode, Endian.big);
    buffer.setUint32(6, repeat, Endian.big);
    buffer.setUint32(10, metaState, Endian.big);
    return buffer.buffer.asUint8List(0, 14);
  }

  /// Serialize text event to bytes
  /// Format:
  /// - 1 byte: type = 1
  /// - 4 bytes: length (uint32)
  /// - N bytes: text bytes (UTF-8)
  static Uint8List serializeTextEvent(String text) {
    final textBytes = utf8.encode(text);
    final len = textBytes.length;
    final buffer = ByteData(5 + len);
    buffer.setUint8(0, 1); // type = 1 (inject text)
    buffer.setUint32(1, len, Endian.big);
    for (int i = 0; i < len; i++) {
      buffer.setUint8(5 + i, textBytes[i]);
    }
    return buffer.buffer.asUint8List();
  }
}
