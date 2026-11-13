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
          ? disambiguate(base, protocol, identity.shortCode)
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
