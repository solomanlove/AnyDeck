import 'dart:convert';

import 'package:any_deck/app/settings/harmony_share_preference_keys.dart';
import 'package:any_deck/core/nearby_share/share_batch_contract.dart';
import 'package:any_deck/core/nearby_share/share_local_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('名称按 UTF-8 字节限制，合法名称不被截断或改写', () {
    for (final name in [
      'AnyDeck',
      '测试 Mac',
      'a' * 24,
      '中' * 8,
      '😀' * 6,
      '👩‍💻 Mac',
      'My Mac',
    ]) {
      ShareLocalName.validate(name);
      final request = ShareBatchRequest(
        [const ShareBatchFile('/synthetic/a', 1)],
        localName: name,
      ).request(localIp: '192.168.1.2', peerIp: '192.168.1.3', port: 44800);
      expect(request['local_name'], name);
      expect(utf8.encode(name).length, lessThanOrEqualTo(24));
    }
    for (final name in [
      '',
      'a' * 25,
      '中' * 9,
      '😀' * 7,
      ' Mac',
      'Mac ',
      'Mac\n',
      'Mac\t',
      'Mac\u0000',
      'Mac\u0085',
      'Mac\u00a0',
      'Mac\u1680',
      'Mac\u2000',
      'Mac\u200a',
      'Mac\u2028',
      'Mac\u2029',
      'Mac\u202f',
      'Mac\u205f',
      'Mac\u3000',
      'Mac\ud800',
    ]) {
      expect(
        () => ShareLocalName.validate(name),
        throwsFormatException,
        reason: 'Rejected ${name.runes.toList()}',
      );
      expect(
        () => ShareBatchRequest([
          const ShareBatchFile('/synthetic/a', 1),
        ], localName: name),
        throwsFormatException,
      );
    }
  });

  test('缺省名称为 AnyDeck，每轮重读磁盘，非法持久化值明确失败', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await ShareLocalName.resolve(), 'AnyDeck');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(HarmonySharePreferenceKeys.localName, '测试 Mac');
    expect(await ShareLocalName.resolve(), '测试 Mac');
    await prefs.setString(HarmonySharePreferenceKeys.localName, 'bad\n');
    await expectLater(ShareLocalName.resolve(), throwsFormatException);
  });
}
