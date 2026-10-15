import 'dart:convert';

import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('HarmonyOS 终端使用鸿蒙默认收藏命令', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final commands = container.read(favoriteCommandsProvider(true));

    expect(commands.map((item) => item.command), [
      'bm dump -a',
      "hidumper -s WindowManagerService -a '-a'",
      'uitest screenCap -p /data/local/tmp/screenshot.png',
      'param get const.ohos.fullname',
      'hilog -x',
      'ifconfig wlan0',
    ]);
  });

  test('Android 终端继续使用 Android 默认收藏命令', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final commands = container.read(favoriteCommandsProvider(false));

    expect(commands.first.command, 'pm list packages');
    expect(commands.map((item) => item.command), isNot(contains('bm dump -a')));
  });

  test('HarmonyOS 默认项删除记录不影响 Android，且自定义收藏仍会载入', () async {
    SharedPreferences.setMockInitialValues({
      'terminal.favorites.deleted_defaults.harmony': [
        'harmony_default_packages',
      ],
      'terminal.favorites': [
        jsonEncode({
          'id': 'custom_1',
          'title': '自定义命令',
          'command': 'echo custom',
          'isCustom': true,
        }),
      ],
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(favoriteCommandsProvider(true));
    container.read(favoriteCommandsProvider(false));
    await Future<void>.delayed(Duration.zero);

    final harmony = container.read(favoriteCommandsProvider(true));
    final android = container.read(favoriteCommandsProvider(false));
    expect(harmony.map((item) => item.command), isNot(contains('bm dump -a')));
    expect(android.map((item) => item.command), contains('pm list packages'));
    expect(harmony.map((item) => item.command), contains('echo custom'));
    expect(android.map((item) => item.command), contains('echo custom'));
  });
}
