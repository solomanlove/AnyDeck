import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:any_deck/features/devices/model/device_list_presentation.dart';

void main() {
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
        DeviceListPresentation.matches(device, '荣耀 Magic', query, true),
        true,
      );
    }
    expect(
      DeviceListPresentation.matches(device, '荣耀 Magic', 'absent', false),
      false,
    );
    final offline = device.copyWith(isOnline: false, status: 'offline');
    expect(
      DeviceListPresentation.matches(offline, '荣耀 Magic', '', true),
      false,
    );
    expect(
      DeviceListPresentation.matches(offline, '荣耀 Magic', '', false),
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
}
