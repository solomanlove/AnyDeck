import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'receiver_identity.dart';

/// 自动名称迁移与重名记录共用规则；自定义名称不按前缀猜测或覆盖。
class ReceiverNames {
  const ReceiverNames({
    required this.airplay,
    required this.dlna,
    required this.defaultAirplay,
    required this.defaultDlna,
  });

  static const conflictKey = 'settings.receiverNameConflicts';
  static const _codeLengthsKey = 'settings.receiverNameCodeLengths';
  static String nameKey(String protocol) => protocol == 'AirPlay'
      ? 'settings.airplayServerName'
      : 'settings.dlnaServerName';
  static String autoKey(String protocol) =>
      'settings.receiverAutoName.$protocol';

  final String airplay;
  final String dlna;
  final String defaultAirplay;
  final String defaultDlna;

  /// Bonjour 的 RAOP 名称还带 13 字节前缀，显示名称限制为 50 UTF-8 字节。
  static String truncate(String value, int maxBytes) {
    final result = StringBuffer();
    var bytes = 0;
    for (final rune in value.runes) {
      final char = String.fromCharCode(rune);
      bytes += utf8.encode(char).length;
      if (bytes > maxBytes) break;
      result.write(char);
    }
    return result.toString().trimRight();
  }

  static String defaultName(ReceiverIdentity identity, String protocol) {
    final computer = ReceiverIdentity.cleanName(identity.computerName);
    final fallback = Platform.isMacOS ? 'Mac' : 'PC';
    final label = computer.isEmpty
        ? '$fallback-${identity.shortCode}'
        : computer;
    return 'AnyDeck-${truncate(label, 50 - 9 - protocol.length)}-$protocol';
  }

  /// 短码放在协议之前；同名冲突记录持久化，因此重启或对端离线都不换码。
  static String disambiguate(String name, String protocol, String shortCode) {
    final suffix = name.endsWith('-$protocol') ? '-$protocol' : '';
    final base = suffix.isEmpty
        ? name
        : name.substring(0, name.length - suffix.length);
    if (base.endsWith('-$shortCode')) return name;
    return '${truncate(base, 50 - suffix.length - shortCode.length - 1)}-$shortCode$suffix';
  }

  /// 从原名派生稳定后备；已有本机短码只升级长度，不反复拼接或降级。
  static String stableFallback(
    String name,
    String protocol,
    String uuid, {
    int codeLength = 6,
  }) {
    final hex = uuid.replaceAll('-', '').toUpperCase();
    if (![6, 12, 32].contains(codeLength) || hex.length != 32) {
      throw ArgumentError('Invalid AnyDeck receiver fallback identity');
    }
    final suffix = name.endsWith('-$protocol') ? '-$protocol' : '';
    var base = suffix.isEmpty
        ? name
        : name.substring(0, name.length - suffix.length);
    var length = codeLength;
    for (final candidate in [32, 12, 6]) {
      if (base.endsWith('-${hex.substring(0, candidate)}')) {
        base = base.substring(0, base.length - candidate - 1);
        if (candidate > length) length = candidate;
        break;
      }
    }
    final prefix = truncate(
      base,
      50 - suffix.length - length - 1,
    ).replaceFirst(RegExp(r'-+$'), '');
    return '$prefix-${hex.substring(0, length)}$suffix';
  }

  static int conflictCodeLength(
    SharedPreferences prefs,
    String name,
    String protocol,
  ) {
    try {
      final lengths =
          jsonDecode(prefs.getString(_codeLengthsKey) ?? '{}') as Map;
      final length = lengths['$protocol:$name'];
      return [6, 12, 32].contains(length) ? length as int : 6;
    } catch (_) {
      return 6;
    }
  }

  /// 根据已发布后备名记住升级档位，重启后不退回曾冲突的较短名称。
  static Future<void> recordPublishedConflict(
    SharedPreferences prefs,
    String name,
    String protocol,
    String uuid,
    String publishedName,
  ) async {
    var length = 6;
    for (final candidate in [6, 12, 32]) {
      if (stableFallback(name, protocol, uuid, codeLength: candidate) ==
          publishedName) {
        length = candidate;
        break;
      }
    }
    await recordConflict(prefs, name, protocol);
    final previous = conflictCodeLength(prefs, name, protocol);
    if (previous >= length) return;
    Map<String, dynamic> lengths;
    try {
      lengths = Map<String, dynamic>.from(
        jsonDecode(prefs.getString(_codeLengthsKey) ?? '{}') as Map,
      );
    } catch (_) {
      lengths = {};
    }
    lengths['$protocol:$name'] = length;
    if (!await prefs.setString(_codeLengthsKey, jsonEncode(lengths))) {
      throw StateError('Cannot persist AnyDeck receiver fallback length');
    }
  }

  static bool hasConflict(
    SharedPreferences prefs,
    String name,
    String protocol,
  ) => (prefs.getStringList(conflictKey) ?? []).contains('$protocol:$name');

  static Future<void> recordConflict(
    SharedPreferences prefs,
    String name,
    String protocol,
  ) async {
    final conflicts = {...?prefs.getStringList(conflictKey), '$protocol:$name'};
    if (!await prefs.setStringList(conflictKey, conflicts.toList())) {
      throw StateError('Cannot persist AnyDeck receiver name conflict');
    }
  }

  static Future<ReceiverNames> load(
    SharedPreferences prefs,
    ReceiverIdentity identity,
  ) async {
    Future<({String value, String fallback})> resolve(String protocol) async {
      final base = defaultName(identity, protocol);
      final fallback = hasConflict(prefs, base, protocol)
          ? stableFallback(
              base,
              protocol,
              identity.uuid,
              codeLength: conflictCodeLength(prefs, base, protocol),
            )
          : base;
      final raw = prefs.getString(nameKey(protocol))?.trim() ?? '';
      final previous = prefs.getString(autoKey(protocol));
      final automatic =
          raw.isEmpty ||
          raw == 'AnyDeck-$protocol' ||
          raw == 'AnyDeck $protocol' ||
          (previous != null && raw == previous);
      final value = automatic ? fallback : raw;
      if (!await prefs.setString(autoKey(protocol), fallback)) {
        throw StateError('Cannot persist AnyDeck receiver default');
      }
      if (automatic && !await prefs.setString(nameKey(protocol), value)) {
        throw StateError('Cannot persist AnyDeck receiver name');
      }
      return (value: value, fallback: fallback);
    }

    final airplay = await resolve('AirPlay');
    final dlna = await resolve('DLNA');
    return ReceiverNames(
      airplay: airplay.value,
      dlna: dlna.value,
      defaultAirplay: airplay.fallback,
      defaultDlna: dlna.fallback,
    );
  }
}
