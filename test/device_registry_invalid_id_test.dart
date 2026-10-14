import 'dart:convert';

import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 验证设备注册表会清理历史无序列号占位记录及其关联缓存。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('removes invalid placeholder device ids from persisted registry', () async {
    const invalidId = '(no serial number)';
    const validId = 'valid-device';
    SharedPreferences.setMockInitialValues({
      'devices.history': [invalidId, validId],
      'devices.aliases': jsonEncode({invalidId: '异常设备', validId: '主力机'}),
      'devices.models': jsonEncode({invalidId: invalidId, validId: 'Pixel'}),
      'devices.products': jsonEncode({invalidId: '-', validId: 'pixel'}),
      'devices.ips': jsonEncode({invalidId: '-', validId: '192.168.1.2'}),
      'devices.androidVersions': jsonEncode({
        invalidId: '-',
        validId: 'Android 16 (API 36)',
      }),
      'devices.sdkVersions': jsonEncode({invalidId: 1, validId: 36}),
      'devices.remarks': jsonEncode({invalidId: '异常', validId: '正常'}),
      'devices.tags': jsonEncode({
        invalidId: ['异常'],
        validId: ['测试机'],
      }),
      'devices.overview.$invalidId': jsonEncode({'name': invalidId}),
    });

    final data = await DeviceRegistryStorage().loadFromPrefs(const []);
    final prefs = await SharedPreferences.getInstance();

    expect(data.historyIds, [validId]);
    expect(data.aliases, isNot(contains(invalidId)));
    expect(data.models, isNot(contains(invalidId)));
    expect(data.products, isNot(contains(invalidId)));
    expect(data.ipAddresses, isNot(contains(invalidId)));
    expect(data.androidVersions, isNot(contains(invalidId)));
    expect(data.sdkVersions, isNot(contains(invalidId)));
    expect(data.remarks, isNot(contains(invalidId)));
    expect(data.tags, isNot(contains(invalidId)));
    expect(prefs.getStringList('devices.history'), [validId]);
    expect(prefs.containsKey('devices.overview.$invalidId'), isFalse);
  });
}
