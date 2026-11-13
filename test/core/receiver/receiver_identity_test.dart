import 'dart:convert';

import 'package:any_deck/core/receiver/receiver_identity.dart';
import 'package:any_deck/core/receiver/receiver_names.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const identity = ReceiverIdentity(
    uuid: 'a7b2c300-0000-4000-8000-000000000001',
    computerName: '办公室 Mac',
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('随机安装身份持久化，电脑改名后短码与 UUID 均保持不变', () async {
    final prefs = await SharedPreferences.getInstance();
    final first = await ReceiverIdentity.load(
      preferences: prefs,
      computerNameReader: () async => '办公室 Mac',
    );
    final second = await ReceiverIdentity.load(
      preferences: prefs,
      computerNameReader: () async => '会议室 Mac',
    );
    expect(second.uuid, first.uuid);
    expect(second.shortCode, first.shortCode);
    expect(second.computerName, '会议室 Mac');
    expect(
      first.uuid,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(prefs.getString(ReceiverIdentity.preferenceKey), first.uuid);
  });

  test('中文电脑名优先，名称不可读时两个协议共用固定短码', () async {
    expect(
      ReceiverNames.defaultName(identity, 'AirPlay'),
      'AnyDeck-办公室 Mac-AirPlay',
    );
    expect(ReceiverNames.defaultName(identity, 'DLNA'), 'AnyDeck-办公室 Mac-DLNA');
    final unavailable = await ReceiverIdentity.load(
      computerNameReader: () async => throw StateError('Unavailable'),
    );
    for (final protocol in ['AirPlay', 'DLNA']) {
      expect(
        ReceiverNames.defaultName(unavailable, protocol),
        endsWith('-${unavailable.shortCode}-$protocol'),
      );
    }
    expect(ReceiverIdentity.cleanName('localhost.local'), isEmpty);
    expect(ReceiverIdentity.cleanName('  办公室\nMac.local  '), '办公室Mac');
  });

  test('长中文名称按 UTF-8 完整码点截断并保留品牌和协议', () {
    final long = ReceiverIdentity(
      uuid: identity.uuid,
      computerName: '电脑😀' * 30,
    );
    final base = ReceiverNames.defaultName(long, 'AirPlay');
    final unique = ReceiverNames.disambiguate(
      base,
      'AirPlay',
      identity.shortCode,
    );
    for (final value in [base, unique]) {
      expect(utf8.encode(value).length, lessThanOrEqualTo(50));
      expect(utf8.decode(utf8.encode(value)), value);
      expect(value, startsWith('AnyDeck-'));
      expect(value, endsWith('-AirPlay'));
    }
    expect(unique, contains('-A7B2C3-AirPlay'));
    expect(
      ReceiverNames.disambiguate(unique, 'AirPlay', identity.shortCode),
      unique,
    );
  });

  test('旧默认迁移，自动名跟随电脑改名，已有自定义名称原样保留', () async {
    SharedPreferences.setMockInitialValues({
      ReceiverNames.nameKey('AirPlay'): 'AnyDeck-AirPlay',
      ReceiverNames.nameKey('DLNA'): 'AnyDeck DLNA',
    });
    final prefs = await SharedPreferences.getInstance();
    final first = await ReceiverNames.load(prefs, identity);
    expect(first.airplay, 'AnyDeck-办公室 Mac-AirPlay');
    expect(first.dlna, 'AnyDeck-办公室 Mac-DLNA');
    final renamed = ReceiverIdentity(uuid: identity.uuid, computerName: '会议室');
    final second = await ReceiverNames.load(prefs, renamed);
    expect(second.airplay, 'AnyDeck-会议室-AirPlay');
    await prefs.setString(
      ReceiverNames.nameKey('AirPlay'),
      'AnyDeck-AirPlay-FKW',
    );
    await prefs.setString(ReceiverNames.nameKey('DLNA'), '我的电视');
    final custom = await ReceiverNames.load(prefs, identity);
    expect(custom.airplay, 'AnyDeck-AirPlay-FKW');
    expect(custom.dlna, '我的电视');
    expect(custom.defaultAirplay, first.defaultAirplay);
  });

  test('重名记录重启后仍生效，并且不改写用户自定义名称', () async {
    final prefs = await SharedPreferences.getInstance();
    final base = ReceiverNames.defaultName(identity, 'AirPlay');
    await ReceiverNames.recordConflict(prefs, base, 'AirPlay');
    final first = await ReceiverNames.load(prefs, identity);
    final second = await ReceiverNames.load(prefs, identity);
    expect(first.airplay, 'AnyDeck-办公室 Mac-A7B2C3-AirPlay');
    expect(second.airplay, first.airplay);
    await prefs.setString(ReceiverNames.nameKey('AirPlay'), '会议室');
    await ReceiverNames.recordConflict(prefs, '会议室', 'AirPlay');
    final custom = await ReceiverNames.load(prefs, identity);
    expect(custom.airplay, '会议室');
    expect(
      ReceiverNames.disambiguate(custom.airplay, 'AirPlay', identity.shortCode),
      '会议室-A7B2C3',
    );
    expect(prefs.getString(ReceiverNames.nameKey('AirPlay')), '会议室');
  });
}
