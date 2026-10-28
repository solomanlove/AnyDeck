import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../app/settings/harmony_share_preference_keys.dart';

/// 与原生 Core 共用的显示名称边界；按 UTF-8 字节计数，不截断或静默改写。
abstract final class ShareLocalName {
  static const defaultName = 'AnyDeck';
  static const maxBytes = 24;

  static void validate(String value) {
    if (value.isEmpty ||
        utf8.encode(value).length > maxBytes ||
        value.startsWith(' ') ||
        value.endsWith(' ') ||
        value.runes.any(
          (rune) =>
              rune < 32 ||
              (rune >= 127 && rune <= 159) ||
              rune == 0xa0 ||
              rune == 0x1680 ||
              (rune >= 0x2000 && rune <= 0x200a) ||
              rune == 0x2028 ||
              rune == 0x2029 ||
              rune == 0x202f ||
              rune == 0x205f ||
              rune == 0x3000 ||
              (rune >= 0xd800 && rune <= 0xdfff),
        )) {
      throw const FormatException('Invalid local name');
    }
  }

  /// 每个新会话重新读取；错误配置明确失败，避免界面与广播身份不一致。
  static Future<String> resolve() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final value =
        prefs.getString(HarmonySharePreferenceKeys.localName) ?? defaultName;
    validate(value);
    return value;
  }
}
