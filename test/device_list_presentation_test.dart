import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:any_deck/features/devices/model/device_list_presentation.dart';

void main() {
  const zh = AppLocalizations(Locale('zh'));
  const device = RegisteredDevice(
    id: 'serial-1',
    status: 'device',
    isOnline: true,
    model: 'PNM_AN10',
    ipAddress: '192.168.1.20',
    remark: 'QA phone',
  );
  test('自定义名称优先商品名，商品名优先型号；缺少资料时回退', () {
    expect(DeviceListPresentation.name(device, '荣耀 Magic'), '荣耀 Magic');
    expect(
      DeviceListPresentation.name(
        device.copyWith(customName: '工作机'),
        '荣耀 Magic',
      ),
      '工作机',
    );
    expect(DeviceListPresentation.name(device, '-'), 'PNM AN10');
    expect(DeviceListPresentation.name(device, null), 'PNM AN10');
  });
  test('名称、IP、序列号、型号与备注可搜索，在线筛选与搜索组合生效', () {
    for (final query in ['荣耀', '192.168', 'SERIAL-1', 'PNM_AN10', 'qa']) {
      expect(
        DeviceListPresentation.matches(
          device,
          '荣耀 Magic',
          query,
          true,
          l10n: zh,
        ),
        true,
      );
    }
    expect(
      DeviceListPresentation.matches(
        device,
        '荣耀 Magic',
        'absent',
        false,
        l10n: zh,
      ),
      false,
    );
    final offline = device.copyWith(isOnline: false, status: 'offline');
    expect(
      DeviceListPresentation.matches(offline, '荣耀 Magic', '', true, l10n: zh),
      false,
    );
    expect(
      DeviceListPresentation.matches(offline, '荣耀 Magic', '', false, l10n: zh),
      true,
    );
    expect(DeviceListPresentation.statusKey(offline), 'deviceOffline');
    expect(
      DeviceListPresentation.statusKey(
        offline.copyWith(status: 'unauthorized'),
      ),
      'deviceUnauthorizedLabel',
    );
  });

  test('按发现类型展示模拟器标签并支持搜索，保留已有自定义标签', () {
    const en = AppLocalizations(Locale('en'));
    final android = device.copyWith(id: 'emulator-5554', tags: ['测试机']);
    final avd = android.copyWith(
      id: 'emulator-avd-Api36',
      emulatorAvdName: 'Api36',
      status: 'offline',
      isOnline: false,
    );
    final legacyHarmony = device.copyWith(id: 'emulator-5556', isHarmony: true);
    final harmony = device.copyWith(
      id: '127.0.0.1:5555',
      isHarmony: true,
      isHarmonyEmulator: true,
    );
    for (final emulator in [android, avd, legacyHarmony, harmony]) {
      expect(DeviceListPresentation.tags(emulator, zh), [
        '模拟器',
        ...emulator.tags,
      ]);
      expect(DeviceListPresentation.tags(emulator, en).first, 'Emulator');
      expect(
        DeviceListPresentation.matches(emulator, '设备', '模拟器', false, l10n: zh),
        isTrue,
      );
    }
    expect(
      DeviceListPresentation.tags(
        android.copyWith(tags: ['测试机', 'emulator']),
        zh,
      ),
      ['测试机', 'emulator'],
    );
    final harmonyPhone = harmony.copyWith(isHarmonyEmulator: false);
    for (final phone in [device, harmonyPhone]) {
      expect(DeviceListPresentation.tags(phone, zh), isEmpty);
      expect(
        DeviceListPresentation.matches(phone, '设备', '模拟器', false, l10n: zh),
        isFalse,
      );
    }
  });
}
