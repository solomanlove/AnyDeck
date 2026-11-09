import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter_test/flutter_test.dart';

const _shared = '127.0.0.1:42345';
List<RegisteredDevice> _merge(
  List<DiscoveredDevice> devices, {
  bool usb = false,
}) => DeviceRegistryMerger.mergeDevices(
  activeDevices: devices,
  historyIds: [if (usb) 'PHONE', _shared],
  aliases: const {},
  models: const {},
  products: const {_shared: 'anydeck_shared_device'},
  ipAddresses: const {},
  androidVersions: const {},
  sdkVersions: const {},
  remarks: const {},
  tags: const {},
  checkedIds: const {},
  serialMap: const {_shared: 'PHONE'},
);

/// 共享离线历史不进入设备列表，同一物理手机的本地通道保持独立。
void main() {
  test('共享断开后不在设备管理保留离线项', () {
    expect(_merge([]), isEmpty);
    expect(
      _merge(const [DiscoveredDevice(id: _shared, status: 'offline')]),
      isEmpty,
    );
  });
  test('连接中的共享设备正常展示', () {
    final device = _merge(const [
      DiscoveredDevice(
        id: _shared,
        status: 'device',
        product: 'anydeck_shared_device',
      ),
    ]).single;
    expect(device.isOnline, isTrue);
    expect(device.isShared, isTrue);
  });
  test('断开共享只移除共享通道，同序列号 USB 历史仍保留', () {
    final device = _merge([], usb: true).single;
    expect(device.id, 'PHONE');
    expect(device.isShared, isFalse);
  });
  test('本地 USB 在线时断开共享，不影响本地设备和命令选路', () {
    final device = _merge(const [
      DiscoveredDevice(id: 'PHONE', status: 'device'),
    ], usb: true).single;
    expect(device.preferredCommandId, 'PHONE');
    expect(device.connections, ['PHONE']);
    expect(device.isOnline, isTrue);
  });
  test('旧回环端口后来被其他在线设备使用时，不被历史共享标记隐藏', () {
    final device = _merge(const [
      DiscoveredDevice(
        id: _shared,
        status: 'device',
        product: 'another_device',
      ),
    ]).single;
    expect(device.isShared, isFalse);
  });
}
